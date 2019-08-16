abstract type System end

import Base: filter
const VarTuple = NamedTuple{(:name, :type)}
filter(f, s::S) where {S<:System} = filter(f, VarTuple.(zip(fieldnames(S), fieldtypes(S))))

update!(s::System) = foreach(t -> value!(s, t.name), filter(t -> t.type <: Var, s))

import Base: length, iterate
length(::System) = 1
iterate(s::System) = (s, nothing)
iterate(s::System, i) = nothing

import Base: broadcastable
broadcastable(s::System) = Ref(s)

import Base: collect
collect(s::System; recursive=true, exclude_self=true) = begin
    S = Set()
    visit(s) = begin
        ST = filter(t -> t.type <: Union{System, Vector{System}, Var{Produce}}, s)
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

context(s::System) = s.context

# import Base: getproperty
# getproperty(s::System, n::Symbol) = value!(s, n)

import Base: show
show(io::IO, s::S) where {S<:System} = print(io, "[$(string(S))]")

export System, update!
