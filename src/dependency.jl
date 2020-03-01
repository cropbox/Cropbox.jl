using LightGraphs
import DataStructures: OrderedDict

struct Dependency
    g::DiGraph
    N::Vector{VarNode}
    I::Dict{VarNode,Int}
    M::Dict{Symbol,VarInfo}
end

dependency(V::Vector{VarInfo}) = begin
    M = Dict{Symbol,VarInfo}()
    for v in V
        for n in names(v)
            M[n] = v
        end
    end
    d = Dependency(DiGraph(), VarNode[], Dict{VarNode,VarInfo}(), M)
    add!(d, V)
    d
end
dependency(V::OrderedDict{Symbol,VarInfo}) = dependency(collect(values(V)))
dependency(::Type{S}) where {S<:System} = dependency(geninfos(S))

node!(d::Dependency, n::VarNode) = begin
    if !haskey(d.I, n)
        add_vertex!(d.g)
        push!(d.N, n)
        d.I[n] = length(d.N)
        #@show "new vertex at $(d.I[n])"
    end
    n
end
node!(d::Dependency, v::VarInfo, t::VarStep) = node!(d, VarNode(v, t))
node!(d::Dependency, v::Symbol, t::VarStep) = node!(d, VarNode(d.M[v], t))
prenode!(d::Dependency, v) = node!(d, v, PreStep())
mainnode!(d::Dependency, v) = node!(d, v, MainStep())
postnode!(d::Dependency, v) = node!(d, v, PostStep())

firstnode(d::Dependency, v::VarInfo) = begin
    for t in (PreStep, MainStep, PostStep)
        n = VarNode(v, t())
        haskey(d.I, n) && return n
    end
    @error "no node found for $a"
end

extract(v::VarInfo; equation=true, tag=true) = begin
    pick(a) = let k, v; extractfuncargdep(@capture(a, k_=v_) ? v : a) end
    pack(A) = filter(!isnothing, pick.(A)) |> Tuple
    eq = equation ? pack(v.args) : ()
    #@show eq
    #HACK: exclude internal tags (i.e. _type)
    tags = filter(!isnothing, [extractfuncargdep(p[2]) for p in v.tags if !startswith(String(p[1]), "_")]) |> Tuple
    par = tag ? tags : ()
    #@show par
    Set([eq..., par...]) |> collect
end

link!(d::Dependency, v::VarInfo, n::VarNode; kwargs...) = begin
    A = extract(v; kwargs...)
    V = [d.M[a] for a in A]
    for v0 in V
        if v0 == v || v0.state == :Solve
            n0 = prenode!(d, v0)
            link!(d, n0, n)
        elseif isnothing(v0.state) && istag(v0, :context)
            n1 = mainnode!(d, v0)
            n2 = postnode!(d, v0)
            link!(d, n1, n)
            link!(d, n, n2)
        else
            n1 = mainnode!(d, v0)
            link!(d, n1, n)
        end
    end
end

link!(d::Dependency, a::VarNode, b::VarNode) = begin
    #@show "link: add edge $(a.info.name) ($(d.I[a])) => $(b.info.name) ($(d.I[b]))"
    add_edge!(d.g, d.I[a], d.I[b])
end

add!(d::Dependency, v::VarInfo) = begin
    #@show "add! $v"
    if v.state == :Accumulate
        # split pre/main nodes to handle self dependency
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        n2 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, n1, n2)
        # needs `time` tags update, but equation args should be excluded due to cyclic dependency
        link!(d, v, n0; equation=false)
        link!(d, v, n2)
    elseif v.state == :Capture
        n0 = mainnode!(d, v)
        n1 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, v, n0; equation=false)
        link!(d, v, n1)
    elseif v.state == :Solve
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        link!(d, n0, n1)
        # needs `lower/upper` tags
        link!(d, v, n0; equation=false)
        link!(d, v, n1)
        # needs access to context in Solve constructor
        c = mainnode!(d, :context)
        link!(d, c, n0)
    elseif v.state == :Flag
        n0 = mainnode!(d, v)
        n1 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, v, n1)
    elseif v.state == :Produce
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        n2 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, n1, n2)
        # no tag available for produce, but just in case we need one later
        link!(d, v, n0; equation=false)
        link!(d, v, n1)
        link!(d, v, n2)
        # needs access to context in Produce constructor
        c = mainnode!(d, :context)
        link!(d, c, n0)
    elseif isnothing(v.state) && istag(v, :context)
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        n2 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, n1, n2)
        link!(d, v, n0)
        link!(d, v, n2)
    else
        n = mainnode!(d, v)
        link!(d, v, n)
    end
    if istag(v, :parameter)
        c = mainnode!(d, :config)
        n = firstnode(d, v)
        link!(d, c, n)
    end
end
add!(d::Dependency, V::Vector{VarInfo}) = begin
    for v in V
        add!(d, v)
    end
end

sort(d::Dependency) = begin
    @assert isempty(simplecycles(d.g))
    J = topological_sort_by_dfs(d.g)
    [d.N[i] for i in J]
end

label(n::VarNode; alias=false) = begin
    v = n.info
    name = alias && !isnothing(v.alias) ? v.alias : v.name
    name = replace(string(name), "_" => " ")
    tag = begin
        if n.step == PreStep()
            "∘"
        elseif n.step == PostStep()
            "⋆"
        else
            ""
        end
    end
    tag * name
end

import TikzGraphs
plot(d::Dependency; kw...) = TikzGraphs.plot(d.g, label.(d.N; kw...))
plot(::Type{S}; kw...) where {S<:System} = plot(dependency(S); kw...)

import Base: write
import TikzPictures
write(filename::AbstractString, d::Dependency; kw...) = begin
    f = TikzPictures.PDF(string(filename))
    TikzPictures.save(f, plot(d; kw...))
end
write(filename::AbstractString, ::Type{S}; kw...) where {S<:System} = write(filename, dependency(S); kw...)
