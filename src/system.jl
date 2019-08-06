abstract type System end

import Base: filter
const VarTuple = NamedTuple{(:name, :type)}
filter(f, s::S) where {S<:System} = filter(f, VarTuple.(zip(fieldnames(S), fieldtypes(S))))

update!(s::System) = foreach(t -> getvar!(s, t.name), filter(t -> t.type <: Var, s))

import Base: length, iterate
length(::System) = 1
iterate(s::System) = (s, nothing)
iterate(s::System, state) = nothing

import Base: broadcastable
broadcastable(s::System) = Ref(s)

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
