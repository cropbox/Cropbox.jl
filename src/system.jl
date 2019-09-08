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

# init!(s::S) where {S<:System} = begin
#     for a in updatable(S)
#         x = getvar(s, a)
#         patch_default!(s, x, x.equation)
#     end
# end

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

using LightGraphs
#TODO: save VarInfo in each System to figure out dependency
collectstatic(s::System; recursive=true) = begin
    g = DiGraph()
    V = System[]
    I = Dict{System,Int}()
    S = Set{System}()
    visit(s::System) = begin
        @show "visit $s"
        add(d::System) = begin
            i = get(I, d, nothing)
            if isnothing(i)
                add_vertex!(g)
                push!(V, d)
                i = I[d] = length(V)
            end
            i
        end
        add(s)

        link(d::System) = begin
            (s == d) && return
            add(d)
            @show "add edge $s ($(I[s])) -> $d ($(I[d]))"
            add_edge!(g, I[s], I[d])
        end
        link(d::Vector{<:System}) = link.(d)
        D = [getfield(s, n) for n in collectible(s)]
        @show "collectible $D"
        foreach(link, D)

        push!(S, s)
        filter!(d -> d ∉ S, D)
        @show "collectible filtered $D"
        recursive && foreach(visit, D)
    end
    visit(s::Vector{<:System}) = visit.(s)
    visit(s)
    J = topological_sort_by_dfs(g)
    [V[i] for i in J]
end

collectvar(S) = begin
    d = Set{Var}()
    for s in S
        for n in updatable(s)
            push!(d, getvar(s, n))
        end
    end
    d
end

context(s::System) = s.context

# import Base: getproperty
# getproperty(s::System, n::Symbol) = value(s, n)

import Base: show
show(io::IO, s::System) = print(io, "[$(name(s))]")

export System
