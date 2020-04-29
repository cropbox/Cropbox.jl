using LightGraphs

struct Hierarchy
    g::DiGraph
    N::Vector{Symbol}
    I::Dict{Symbol,Int}
    E::Dict{NTuple{2,Int},Symbol}
end

hierarchy() = Hierarchy(DiGraph(), Symbol[], Dict{Symbol,Int}(), Dict{NTuple{2,Int},Symbol}())
hierarchy(S::Type{<:System}) = begin
    h = hierarchy()
    add!(h, S)
    h
end

node!(h::Hierarchy, n::Symbol) = begin
    if !haskey(h.I, n)
        add_vertex!(h.g)
        h.I[n] = nv(h.g)
    end
    n
end
node!(h::Hierarchy, T::Type{<:System}) = node!(h, nameof(T))

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
    a = node!(h, S)
    (a in h.N || hasloop(h, a)) && return
    add!(h, a)
    V = geninfos(S)
    for v in V
        #HACK: evaluate types defined in Main module
        T = Main.eval(v.type)
        #HACK: skip Context since the graph tends to look too busy
        (T == Context) && continue
        add!(h, a, T)
    end
    push!(h.N, a)
end

add!(h::Hierarchy, a::Symbol) = begin
    for M in Cropbox.mixins(Val(a))
        (M == System) && continue
        add!(h, M)
        b = node!(h, M)
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
        "dotted"
    elseif e == :loop
        "loop"
    else
        "solid"
    end
end
edgestyles(h::Hierarchy) = Dict(e => edgestyle(h, s) for (e, s) in h.E)

import TikzGraphs
plot(h::Hierarchy; sib_dist=-1, lev_dist=-1) = begin
    #TikzGraphs.plot(h.g, labels(h), edge_styles=edgestyles(h), options="grow=right, components go down left aligned")
    TikzGraphs.plot(h.g, TikzGraphs.Layouts.Layered(; sib_dist=sib_dist, lev_dist=lev_dist), labels(h), edge_styles=edgestyles(h))
end

import Base: write
import TikzPictures
write(filename::AbstractString, h::Hierarchy; plotopts...) = begin
    f = TikzPictures.PDF(string(filename))
    TikzPictures.save(f, plot(h; plotopts...))
end
