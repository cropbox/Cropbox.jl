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
        ST = filter(t -> t.type <: Union{System, Array{System}}, s)
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

import MacroTools: @capture, @q, striplines

struct StatevarInfo
    var::Symbol
    alias::Union{Symbol,Nothing}
    args::Array
    body
    type::Symbol
    tags::Dict
end

import Base: show
function show(io::IO, s::StatevarInfo)
    println(io, "var: $(s.var)")
    println(io, "alias: $(repr(s.alias))")
    println(io, "func ($(repr(s.args))) = $(repr(s.body))")
    println(io, "type: $(s.type)")
    for (k, v) in s.tags
        println(io, "tag $k = $v")
    end
end

function parse_line(line::Union{Expr,Symbol})
    @capture(line,
        (var_(args__): alias_ => body_ ~ type_(tags__)) |
        (var_(args__): alias_ => body_ ~ type_) |
        (var_(args__) => body_ ~ type_(tags__)) |
        (var_(args__) => body_ ~ type_) |
        (var_: alias_ ~ type_(tags__)) |
        (var_: alias_ ~ type_) |
        (var_ ~ type_(tags__)) |
        (var_ ~ type_)
    )
    args = isnothing(args) ? [] : args
    tags = isnothing(tags) ? [] : tags
    tags = Dict((
        @capture(t, (k_=v_) | k_);
        v = isnothing(v) ? true : v;
        k => v
    ) for t in tags)
    return StatevarInfo(var, alias, args, body, type, tags)
end

generate_field(i::StatevarInfo) = :($(i.var)::Statevar)
generate_statevar(i::StatevarInfo; self) = begin
    if isnothing(i.body)
        @assert isempty(i.args)
        calc = esc(i.var)
    else
        #calc = @q $(Expr(:tuple, i.args...)) -> $(i.body)
        calc = @q function $(i.var)($(Tuple(i.args)...)) $(i.body) end
    end
    type = Symbol(uppercasefirst(string(i.type)))
    name = Meta.quot(Symbol(i.var))
    args = merge(Dict(:time => :($(self).context.clock.tick)), i.tags)
    args = [:($(esc(k))=$v) for (k, v) in args]
    :($(self).$(i.var) = Statevar($self, $calc, $type; name=$name, $(args...)))
end
generate_system(name, infos) = begin
    self = gensym(:self)
    fields = generate_field.(infos)
    statevars = generate_statevar.(infos; self=self)
    quote
        mutable struct $name <: System
            context::System
            parent::System
            children::Array{System}

            $(fields...)

            function $name(;context, parent, children=System[])
                $(self) = new()
                $(self).context = context
                $(self).parent = parent
                $(self).children = children
                $(statevars...)
                $(self)
            end
        end
    end
end

macro system(name, block)
    infos = [parse_line(line) for line in striplines(block).args]
    generate_system(name, infos)
end

export @system
