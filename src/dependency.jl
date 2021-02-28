using LightGraphs: LightGraphs, DiGraph, add_edge!, add_vertex!, dst, edges, src

struct Dependency <: Graph
    g::DiGraph
    N::Vector{VarNode}
    I::Dict{VarNode,Int}
    M::Dict{Symbol,VarInfo}
end

dependency(M::Dict{Symbol,VarInfo}) = Dependency(DiGraph(), VarNode[], Dict{VarNode,VarInfo}(), M)
dependency(V::Vector{VarInfo}) = begin
    M = Dict{Symbol,VarInfo}()
    for v in V
        for n in names(v)
            M[n] = v
        end
    end
    d = dependency(M)
    add!(d, V)
    d
end
dependency(::Type{S}) where {S<:System} = dependency(geninfos(S))
dependency(::S) where {S<:System} = dependency(S)

graph(d::Dependency) = d.g

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

extract(v::VarInfo; equation=true, tag=true, include=(), exclude=()) = begin
    pick(a) = let k, v; extractfuncargdep(@capture(a, k_=v_) ? v : a) end
    pack(A) = Iterators.flatten(filter!(!isnothing, pick.(A))) |> Tuple
    eq = equation ? pack(v.args) : ()
    #@show eq
    #HACK: exclude internal tags (i.e. _type)
    #HACK: filter included/excluded tags
    #TODO: share logic with filterconstructortags() in macro?
    tagfilter(t) = !startswith(String(t), "_") && (isempty(include) ? true : t ∈ include) && (isempty(exclude) ? true : t ∉ exclude)
    par = tag ? Tuple(Iterators.flatten(filter!(!isnothing, [extractfuncargdep(p[2]) for p in v.tags if tagfilter(p[1])]))) : ()
    #@show par
    Set([eq..., par...]) |> collect
end

link!(d::Dependency, v::VarInfo, n::VarNode; kwargs...) = begin
    A = extract(v; kwargs...)
    #HACK: skip missing refs to allow const variable patch syntax (i.e. @system S{x=1})
    V = [d.M[a] for a in A if haskey(d.M, a)]
    for v0 in V
        if v0 == v || v0.state == :Bisect
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
    if v.state == :Accumulate || v.state == :Capture
        # split pre/main nodes to handle self dependency
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        n2 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, n1, n2)
        # needs `time` tags update, but equation args should be excluded due to cyclic dependency
        #HACK: support `when` tag while avoiding cyclic dependency
        #TODO: more elegant way to handle tags include/exclude
        link!(d, v, n0; equation=false, exclude=(:when,))
        link!(d, v, n2; equation=false, include=(:when,))
        link!(d, v, n2)
    elseif v.state == :Bisect
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        link!(d, n0, n1)
        # needs `lower/upper` tags
        link!(d, v, n0; equation=false)
        link!(d, v, n1)
        # needs access to context in Bisect constructor (otherwise convergence would fail)
        c = mainnode!(d, :context)
        link!(d, c, n0)
    elseif v.state == :Produce
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        n2 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, n1, n2)
        # no tag available for produce, but just in case we need one later
        link!(d, v, n0; equation=false)
        link!(d, v, n2)
        # make sure context get updated before updating subtree
        c = mainnode!(d, :context)
        link!(d, c, n1)
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

Base.sort(d::Dependency) = begin
    C = LightGraphs.simplecycles(d.g)
    !isempty(C) && error("no cyclic dependency allowed: $([[d.N[i].info.name for i in c] for c in C])")
    J = LightGraphs.topological_sort_by_dfs(d.g)
    [d.N[i] for i in J]
end

label(n::VarNode; alias=false) = begin
    v = n.info
    name = alias && !isnothing(v.alias) ? v.alias : v.name
    name = string(name)
    tag = string(n.step)
    tag * name
end
labels(d::Dependency; kw...) = label.(d.N; kw...)

edgestyle(d::Dependency, a::VarNode, b::VarNode) = ""
edgestyles(d::Dependency) = Dict(let a=src(e), b=dst(e); (a, b) => edgestyle(d, d.N[a], d.N[b]) end for e in edges(d.g))

Base.show(io::IO, d::Dependency) = print(io, "Dependency")
Base.show(io::IO, ::MIME"text/plain", d::Dependency) = begin
    color = get(io, :color, false)
    VC = tokencolor(VarColor(); color)
    MC = tokencolor(MiscColor(); color)
    print(io, MC("["))
    print(io, join(VC.(label.(sort(d))), MC(" → ")))
    print(io, MC("]"))
end
