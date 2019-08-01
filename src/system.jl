abstract type System end

import Base: filter
const StatevarTuple = NamedTuple{(:name, :type)}
filter(f, s::S) where {S<:System} = filter(f, map(StatevarTuple, zip(fieldnames(S), fieldtypes(S))))

update!(s::System) = foreach(t -> getvar!(s, t.name), filter(t -> t.type <: Statevar, s))

import Base: length, iterate
length(::System) = 1
iterate(s::System) = (s, nothing)
iterate(s::System, state) = nothing

import Base: collect
function collect(s::System; recursive=true, exclude_self=true)
    S = Set()
    visit(s) = begin
        ST = filter(t -> t.type <: Union{System, Vector{System}}, s)
        ST = map(t -> Set(getfield(s, t.name)), ST)
        SS = Set()
        foreach(e -> union!(SS, e), ST)
        filter!(s -> s ∉ S, SS)
        union!(S, SS)
        recursive && foreach(visit, SS)
    end
    visit(s)
    exclude_self && setdiff!(S, [s])
    S
end

import Base: parent
context(s::System) = s.context
parent(s::System) = s.parent
children(s::System) = s.children
#neighbors(s::System) = Set(parent(s)) ∪ children(s)

# import Base: getproperty
# getproperty(s::System, n::Symbol) = getvar!(s, n)

import Base: show
show(io::IO, s::S) where {S<:System} = print(io, "[$(string(S))]")

export System, update!

####

import MacroTools: @capture, @q, flatten, isexpr, striplines

struct VarInfo{S}
    var::Symbol
    alias::Union{Symbol,Nothing}
    args::Array
    body#::Union{Expr,Symbol,Nothing}
    type::Union{Symbol,Expr}
    tags::Dict{Symbol,Any}
end

import Base: show
function show(io::IO, s::VarInfo)
    println(io, "var: $(s.var)")
    println(io, "alias: $(repr(s.alias))")
    println(io, "func ($(repr(s.args))) = $(repr(s.body))")
    println(io, "type: $(s.type)")
    for (k, v) in s.tags
        println(io, "tag $k = $v")
    end
end

function VarInfo(line::Union{Expr,Symbol})
    # name[(args..)][: alias] [=> body] ~ type[(tags..)]
    @capture(line, decl_ ~ deco_)
    @capture(deco, type_(tags__) | type_)
    @capture(decl, (def1_ => body_) | def1_)
    @capture(def1, (def2_: alias_) | def2_)
    @capture(def2, name_(args__) | name_)
    args = isnothing(args) ? [] : args
    symbolify(t) = Symbol(uppercasefirst(string(t)))
    if @capture(type, [elemtype_])
        type = :(Vector{$(symbolify(elemtype))})
    else
        type = symbolify(type)
    end
    tags = isnothing(tags) ? [] : tags
    tags = Dict((
        @capture(t, (k_=v_) | k_);
        v = isnothing(v) ? true : v;
        k => v
    ) for t in tags)
    VarInfo{eval(type)}(name, alias, args, body, type, tags)
end

const self = :($(esc(:self)))

genfield(i::VarInfo{S}) where {S<:State} = genfield(Statevar, i.var, i.alias)
genfield(i::VarInfo{S}) where S = genfield(S, i.var, i.alias)
genfield(S, var, alias) = begin
    v = :($var::$S)
    a = :($alias::$S)
    isnothing(alias) ? v : @q begin $v; $a end
end

genargs(infos::Vector, options) = Tuple(filter(!isnothing, genarg.(infos)))
genarg(i::VarInfo) = begin
    if haskey(i.tags, :usearg)
        if haskey(i.tags, :usedefault)
            Expr(:kw, i.var, :($(i.type)()))
        else
            i.var
        end
    end
end

gendecl(i::VarInfo{S}) where {S<:State} = begin
    if isnothing(i.body)
        @assert isempty(i.args)
        calc = esc(i.var)
    else
        #calc = @q $(Expr(:tuple, i.args...)) -> $(i.body)
        calc = @q function $(i.var)($(Tuple(i.args)...)) $(i.body) end
    end
    name = Meta.quot(Symbol(i.var))
    args = merge(Dict(:time => "context.clock.tick"), i.tags)
    if !isempty(args[:time])
        path = [self; Symbol.(split(args[:time], "."))]
        args[:time] = reduce((a, b) -> :($a.$b), path)
    end
    args = [:($(esc(k))=$v) for (k, v) in args]
    v = :($self.$(i.var) = Statevar($self, $calc, $S; name=$name, $(args...)))
    a = :($self.$(i.alias) = $self.$(i.var))
    isnothing(i.alias) ? v : @q begin $v; $a end
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

export @system
