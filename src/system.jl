abstract type System end

update!(s::System) = foreach(n -> value!(s, n), updatable(s))

name(s::S) where {S<:System} = string(S)
import Base: names
names(s::System) = names(typeof(s))
names(S::Type{<:System}) = (n = split(String(Symbol(S)), "."); [Symbol(join(n[i:end], ".")) for i in 1:length(n)])

import Base: length, iterate
length(::System) = 1
iterate(s::System) = (s, nothing)
iterate(s::System, i) = nothing

import Base: broadcastable
broadcastable(s::System) = Ref(s)

import Base: getindex
getindex(s::System, i) = getproperty(s, i)

import Base: getproperty
getproperty(s::System, n::String) = getvar(s, n)

import Base: collect
collect(s::System; recursive=true, exclude_self=true) = begin
    S = Set{System}()
    SS = Set{System}()
    visit(s) = begin
        empty!(SS)
        add(f::System) = push!(SS, f)
        add(f) = union!(SS, f)
        for n in collectible(s)
            add(getfield(s, n))
        end
        filter!(s -> s ∉ S, SS)
        union!(S, SS)
        recursive && foreach(visit, SS)
    end
    visit(s)
    exclude_self && setdiff!(S, (s,))
    S
end

filtervar(type::Type, ::Type{S}) where {S<:System} = begin
    d = collect(zip(fieldnames(S), fieldtypes(S)))
    filter!(p -> p[2] <: type, d)
    map(p -> p[1], d)::Vector{Symbol}
end
@generated collectible(::Type{S}) where {S<:System} = begin
    v = filtervar(Union{System, Vector{System}, Var{Produce}}, S)
    :($v)
end
collectible(::S) where {S<:System} = collectible(S)
@generated updatable(::Type{S}) where {S<:System} = begin
    v = filtervar(Var, S)
    :($v)
end
updatable(::S) where {S<:System} = updatable(S)

context(s::System) = s.context

# import Base: getproperty
# getproperty(s::System, n::Symbol) = value!(s, n)

import Base: show
show(io::IO, s::System) = print(io, "[$(name(s))]")

export System
