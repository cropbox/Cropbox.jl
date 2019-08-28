abstract type System end

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

collectible(::S) where {S<:System} = collectible(S)
updatable(::S) where {S<:System} = updatable(S)

import Base: collect
import DataStructures: OrderedSet
collect(s::System; recursive=true, exclude_self=false) = begin
    S = OrderedSet{System}()
    visit(s) = begin
        T = OrderedSet{System}()
        add(f::System) = push!(T, f)
        add(f) = union!(T, f)
        for n in collectible(s)
            add(getfield(s, n))
        end
        filter!(s -> s ∉ S, T)
        union!(S, T)
        recursive && foreach(visit, T)
    end
    visit(s)
    exclude_self && setdiff!(S, (s,))
    S
end

import DataStructures: DefaultDict
collectvar_dd(S::AbstractSet) = begin
    d = DefaultDict{Int,Vector{Tuple{System,Symbol}}}(Vector{Tuple{System,Symbol}})
    for s in S
        u = updatable(s)
        for (i, t) in u
            for n in t
                push!(d[i], (s, n))
            end
        end
    end
    vcat([d[k] for k in sort(collect(keys(d)))]...)
end

import DataStructures: PriorityQueue, enqueue!
collectvar_pq(S::AbstractSet) = begin
    q = PriorityQueue{Tuple{System,Symbol},Int}(Base.Reverse)
    for s in S
        u = updatable(s)
        for (i, t) in u
            for n in t
                enqueue!(q, (s, n), i)
            end
        end
    end
    q |> collect |> Iterators.reverse |> collect
end
collectvar(S) = collectvar_pq(S)

context(s::System) = s.context

# import Base: getproperty
# getproperty(s::System, n::Symbol) = value!(s, n)

import Base: show
show(io::IO, s::System) = print(io, "[$(name(s))]")

export System
