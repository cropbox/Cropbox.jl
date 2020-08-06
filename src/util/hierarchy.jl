import LightGraphs: LightGraphs, DiGraph, add_edge!, add_vertex!, has_edge, nv

struct Hierarchy <: Graph
    g::DiGraph
    N::Vector{Symbol}
    I::Dict{Symbol,Int}
    E::Dict{NTuple{2,Int},Symbol}
    C::Dict{Symbol,Any}
end

hierarchy(C=()) = Hierarchy(DiGraph(), Symbol[], Dict{Symbol,Int}(), Dict{NTuple{2,Int},Symbol}(), Dict{Symbol,Any}(C))
hierarchy(S::Type{<:System}; kw...) = begin
    h = hierarchy(kw)
    add!(h, S)
    h
end
hierarchy(::S; kw...) where {S<:System} = hierarchy(S; kw...)

graph(h::Hierarchy) = h.g

node!(h::Hierarchy, n::Symbol) = begin
    if !haskey(h.I, n)
        add_vertex!(h.g)
        h.I[n] = nv(h.g)
    end
    n
end
node!(h::Hierarchy, T::Type{<:System}) = node!(h, namefor(T))

import DataStructures: SortedDict
nodes(h::Hierarchy) = SortedDict(v => k for (k, v) in h.I) |> values |> collect

hasloop(h::Hierarchy, n::Symbol) = (i = h.I[n]; has_edge(h.g, i, i))

link!(h::Hierarchy, a::Symbol, b::Symbol, e=nothing) = begin
    ai = h.I[a]
    bi = h.I[b]
    add_edge!(h.g, ai, bi)
    (ai == bi) && (e = :loop)
    !isnothing(e) && (h.E[(ai, bi)] = e)
end

add!(h::Hierarchy, S::Type{<:System}) = begin
    #HACK: evaluation scope is the module where S was originally defined
    scope = S.name.module
    a = node!(h, S)
    (a in h.N || hasloop(h, a)) && return
    add!(h, a, mixins(S))
    V = geninfos(S)
    for v in V
        T = @eval scope $(v.type)
        #HACK: skip Context since the graph tends to look too busy
        get(h.C, :skipcontext, false) && (T == Context) && continue
        add!(h, a, T)
    end
    push!(h.N, a)
end

add!(h::Hierarchy, a::Symbol, M::Tuple) = begin
    for m in M
        (m == System) && continue
        add!(h, m)
        b = node!(h, m)
        link!(h, b, a, :mixin)
    end
end
add!(h::Hierarchy, a::Symbol, T::Type{<:System}) = begin
    b = node!(h, T)
    link!(h, b, a)
    add!(h, T)
end
add!(h::Hierarchy, a::Symbol, T::Type{Vector{<:System}}) = foreach(b -> add!(h, a, b), T)
add!(h::Hierarchy, a::Symbol, T) = nothing

label(n::Symbol) = string(n)
labels(h::Hierarchy) = label.(nodes(h))

edgestyle(h::Hierarchy, e::Symbol) = begin
    if e == :mixin
        "dashed"
    elseif e == :loop
        "loop"
    else
        "solid"
    end
end
edgestyles(h::Hierarchy) = Dict(e => edgestyle(h, s) for (e, s) in h.E)

plot(h::Hierarchy; sib_dist=-1, lev_dist=-1) = plot(h, (; sib_dist=sib_dist, lev_dist=lev_dist))

Base.show(io::IO, h::Hierarchy) = print(io, "Hierarchy")
Base.show(io::IO, ::MIME"text/plain", h::Hierarchy) = begin
    color = get(io, :color, false)
    SC = tokencolor(SystemColor(); color=color)
    MC = tokencolor(MiscColor(); color=color)
    print(io, MC("{"))
    print(io, join(SC.(labels(h)), MC(", ")))
    print(io, MC("}"))
end
