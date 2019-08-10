using MacroTools
import MacroTools: @q, flatten, striplines

struct VarInfo{S}
    var::Symbol
    alias::Vector{Symbol}
    args::Vector
    body#::Union{Expr,Symbol,Nothing}
    state::Symbol
    type::Union{Symbol,Expr,Nothing}
    tags::Dict{Symbol,Any}
end

import Base: show
function show(io::IO, s::VarInfo)
    println(io, "var: $(s.var)")
    println(io, "alias: $(s.alias)")
    println(io, "func ($(repr(s.args))) = $(repr(s.body))")
    println(io, "state: $(s.state)")
    println(io, "type: $(repr(s.type))")
    for (k, v) in s.tags
        println(io, "tag $k = $v")
    end
end

function VarInfo(line::Union{Expr,Symbol})
    # name[(args..)][: alias] [=> body] ~ [state][::type][(tags..)]
    @capture(line, decl_ ~ deco_)
    @capture(deco, state_::type_(tags__) | ::type_(tags__) | state_(tags__) | state_::type_ | ::type_ | state_)
    @capture(decl, (def1_ => body_) | def1_)
    @capture(def1, (def2_: alias_) | def2_)
    @capture(def2, name_(args__) | name_)
    args = isnothing(args) ? [] : args
    alias = isnothing(alias) ? [] : alias
    state = isnothing(state) ? :Nothing : Symbol(uppercasefirst(string(state)))
    type = @capture(type, [elemtype_]) ? :(Vector{$elemtype}) : type
    tags = isnothing(tags) ? [] : tags
    tags = Dict((
        @capture(t, (k_=v_) | k_);
        v = isnothing(v) ? true : v;
        k => v
    ) for t in tags)
    VarInfo{eval(state)}(name, alias, args, body, state, type, tags)
end

const self = :($(esc(:self)))

genfield(i::VarInfo{S}) where {S<:State} = genfield(Var{S}, i.var, i.alias)
genfield(i::VarInfo{Nothing}) = genfield(esc(i.type), i.var, i.alias)
genfield(S, var, alias) = @q begin
    $var::$S
    $(@q begin $([:($a::$S) for a in alias]...) end)
end

genargs(infos::Vector, options) = Tuple(filter(!isnothing, genarg.(infos)))
genarg(i::VarInfo{Nothing}) = begin
    if haskey(i.tags, :usearg)
        if haskey(i.tags, :usedefault)
            Expr(:kw, i.var, :($(esc(i.type))()))
        else
            i.var
        end
    end
end
genarg(i::VarInfo) = nothing

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
    stargs = [:($(esc(k))=$v) for (k, v) in i.tags]
    if !isnothing(i.type)
        stargs = [:(_type=$(i.type)); stargs]
    end
    @q begin
        $self.$(i.var) = Var($self, $e, $S; _name=$name, _alias=$(i.alias), $(stargs...))
        $(@q begin $([:($self.$a = $self.$(i.var)) for a in i.alias]...) end)
    end
end
gendecl(i::VarInfo{Nothing}) = begin
    if !isnothing(i.body)
        # @assert isnothing(i.args)
        decl = esc(i.body)
    elseif haskey(i.tags, :usearg)
        decl = esc(i.var)
    else
        decl = :($(esc(i.type))())
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
            context ~ ::Context(usearg)
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
