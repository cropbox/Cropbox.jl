using MacroTools
import MacroTools: @q, flatten, striplines

struct VarInfo{S}
    var::Symbol
    alias::Vector{Symbol}
    args::Vector
    body#::Union{Expr,Symbol,Nothing}
    state::Union{Symbol,Expr}
    tags::Dict{Symbol,Any}
end

import Base: show
function show(io::IO, s::VarInfo)
    println(io, "var: $(s.var)")
    println(io, "alias: $(s.alias)")
    println(io, "func ($(repr(s.args))) = $(repr(s.body))")
    println(io, "state: $(s.state)")
    for (k, v) in s.tags
        println(io, "tag $k = $v")
    end
end

function VarInfo(line::Union{Expr,Symbol})
    # name[(args..)][: alias] [=> body] ~ type[(tags..)]
    @capture(line, decl_ ~ deco_)
    @capture(deco, state_(tags__) | state_)
    @capture(decl, (def1_ => body_) | def1_)
    @capture(def1, (def2_: alias_) | def2_)
    @capture(def2, name_(args__) | name_)
    args = isnothing(args) ? [] : args
    alias = isnothing(alias) ? [] : alias
    symbolify(t) = Symbol(uppercasefirst(string(t)))
    if @capture(state, [statetype_])
        state = :(Vector{$(symbolify(statetype))})
    else
        state = symbolify(state)
    end
    tags = isnothing(tags) ? [] : tags
    tags = Dict((
        @capture(t, (k_=v_) | k_);
        v = isnothing(v) ? true : v;
        k => v
    ) for t in tags)
    VarInfo{eval(state)}(name, alias, args, body, state, tags)
end

const self = :($(esc(:self)))

genfield(i::VarInfo{S}) where {S<:State} = genfield(Var, i.var, i.alias)
genfield(i::VarInfo{S}) where S = genfield(S, i.var, i.alias)
genfield(S, var, alias) = @q begin
    $var::$S
    $(@q begin $([:($a::$S) for a in alias]...) end)
end

genargs(infos::Vector, options) = Tuple(filter(!isnothing, genarg.(infos)))
genarg(i::VarInfo) = begin
    if haskey(i.tags, :usearg)
        if haskey(i.tags, :usedefault)
            Expr(:kw, i.var, :($(i.state)()))
        else
            i.var
        end
    end
end

equation(f) = begin
    fdef = splitdef(f)
    name = Meta.quot(fdef[:name])
    key(x::Symbol) = x
    key(x::Expr) = x.args[1]
    args = key.(fdef[:args])
    kwargs = key.(fdef[:kwargs])
    pair(x::Symbol) = nothing
    pair(x::Expr) = x.args[1] => x.args[2]
    default = filter(!isnothing, [pair.(fdef[:args]); pair.(fdef[:kwargs])]) |> Dict
    :(Equation($f, $name, $args, $kwargs, $default))
end

macro equation(f)
    e = eval(equation(f))
    :($(esc(e.name)) = $e)
end

gendecl(i::VarInfo{S}) where {S<:State} = begin
    if isnothing(i.body)
        @assert isempty(i.args)
        e = esc(i.var)
    else
        f = @q function $(i.var)($(Tuple(i.args)...)) $(i.body) end
        e = equation(f)
    end
    name = Meta.quot(i.var)
    tags = [:($(esc(k))=$v) for (k, v) in i.tags]
    @q begin
        $self.$(i.var) = Var($self, $e, $S; name=$name, alias=$(i.alias), $(tags...))
        $(@q begin $([:($self.$a = $self.$(i.var)) for a in i.alias]...) end)
    end
end
gendecl(i::VarInfo{S}) where S = begin
    if !isnothing(i.body)
        # @assert isnothing(i.args)
        decl = esc(i.body)
    elseif haskey(i.tags, :usearg)
        decl = esc(i.var)
    else
        decl = :($S())
    end
    :($self.$(i.var) = $decl)
end

genstruct(name, infos, options) = begin
    fields = genfield.(infos)
    args = genargs(infos, options)
    decls = gendecl.(infos)
    system = @q begin
        mutable struct $name <: System
            $(fields...)
            function $name(; $(args...))
                $self = new()
                $(decls...)
                $self
            end
        end
    end
    flatten(system)
end

gensystem(name, block, options...) = begin
    if :bare ∉ options
        header = @q begin
            context ~ context(usearg)
            parent ~ system(usearg)
            children ~ [system](usearg, usedefault)
        end
        block = flatten(:($header; $block))
    end
    infos = [VarInfo(line) for line in striplines(block).args]
    genstruct(name, infos, options)
end

macro system(name, block, options...)
    gensystem(name, block, options...)
end

export @equation, @system
