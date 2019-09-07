using LightGraphs

struct Dependency{T,U}
    g::DiGraph
    V::Vector{T}
    I::Dict{T,Int}
    M::Dict{Symbol,U}
end

Dependency{T}(M::Dict{Symbol,U}) where {T,U} = Dependency{T,U}(DiGraph(), T[], Dict{T,Int}(), M)

vertex!(d::Dependency{T}, v::T) where T = begin
    if !haskey(d.I, v)
        add_vertex!(d.g)
        push!(d.V, v)
        d.I[v] = length(d.V)
        @show "new vertex at $(d.I[v])"
    end
    v
end
vertex!(d::Dependency, a::Symbol) = vertex!(d, d.M[a])

link!(d::Dependency{T}, a::T, b::T) where T = begin
    @show "link: add edge $a ($(d.I[a])) => $b ($(d.I[b]))"
    add_edge!(d.g, d.I[a], d.I[b])
end
invertices!(d::Dependency{T}, v; _...) where T = ()
inlink!(d::Dependency{T}, v, v1::T; kwargs...) where T = begin
    @show "inlink! v = $v to v1 = $v1"
    for v0 in invertices!(d, v; kwargs...)
        link!(d, v0, v1)
    end
end

add!(d::Dependency, v) = begin
    @show "add! $(v.name)"
    vertex!(d, v)
    inlink!(d, v, v)
end
add!(d::Dependency, V::Vector) = begin
    for v in V
        add!(d, v)
    end
end

sort(d::Dependency) = begin
    @assert isempty(simplecycles(d.g))
    J = topological_sort_by_dfs(d.g)
    [d.V[i] for i in J]
end
