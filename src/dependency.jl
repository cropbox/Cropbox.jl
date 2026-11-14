using Graphs: Graphs, DiGraph, add_edge!, add_vertex!, dst, edges, src

struct Dependency <: Graph
    g::DiGraph
    N::Vector{VarNode}
    I::Dict{VarNode,Int}
    M::Dict{Symbol,VarInfo}
    focus::Set{Symbol}
end

Dependency(g, N, I, M) = Dependency(g, N, I, M, Set{Symbol}())
dependency(M::Dict{Symbol,VarInfo}) = Dependency(DiGraph(), VarNode[], Dict{VarNode,Int}(), M)
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
stylekeys(::Dependency) = (GRAPH_STYLE_KEYS..., :alias, :group)

phasenodes(d::Dependency, v::VarInfo) = filter(
    n -> haskey(d.I, n), VarNode.(Ref(v), (PreStep(), MainStep(), PostStep())),
)
phaseindices(d::Dependency, I) = Set(
    d.I[n] for v in Set(d.N[i].info for i in I) for n in phasenodes(d, v)
)

configindices(d::Dependency, I) = Set(
    j for i in I if istag(d.N[i].info, :parameter)
    for j in Graphs.inneighbors(d.g, i) if d.N[j].info.name == :config
)

checkselection(depth, direction) = begin
    depth >= 0 || throw(ArgumentError("depth must be non-negative"))
    direction in (:up, :down, :both) ||
        throw(ArgumentError("direction must be :up, :down, or :both"))
end

varinfos(d::Dependency, names) = unique(map(names) do name
    haskey(d.M, name) || throw(ArgumentError("variable $(repr(name)) not found"))
    d.M[name]
end)

focusindices(d::Dependency, focus::Symbol; depth, direction) = begin
    target = only(varinfos(d, [focus]))
    I = Set(d.I[n] for n in phasenodes(d, target))
    frontier = copy(I)
    neighbors = direction == :up ? Graphs.inneighbors : direction == :down ? Graphs.outneighbors : Graphs.all_neighbors
    for _ in 1:depth
        adjacent = (j for i in frontier for j in neighbors(d.g, i))
        frontier = setdiff(phaseindices(d, adjacent), I)
        isempty(frontier) && break
        union!(I, frontier)
    end
    I, [target.name]
end

pathnames(x::Symbol) = [x]
pathnames(x::AbstractVector{Symbol}) = begin
    isempty(x) && throw(ArgumentError("path endpoint cannot be empty"))
    unique(x)
end
pathnames(x) = throw(ArgumentError("path endpoint must be a Symbol or a vector of Symbols: $(repr(x))"))

reachable(g, roots, neighbors) = begin
    seen = Set{Int}(roots)
    frontier = collect(roots)
    while !isempty(frontier)
        i = pop!(frontier)
        for j in neighbors(g, i)
            if j ∉ seen
                push!(seen, j)
                push!(frontier, j)
            end
        end
    end
    seen
end

pathindices(d::Dependency, path::Pair) = begin
    sources = pathnames(first(path))
    targets = pathnames(last(path))
    sourceinfo = varinfos(d, sources)
    targetinfo = varinfos(d, targets)
    source = findall(n -> n.info in sourceinfo, d.N)
    target = findall(n -> n.info in targetinfo, d.N)
    forward = reachable(d.g, source, Graphs.outneighbors)
    backward = reachable(d.g, target, Graphs.inneighbors)
    I = intersect(forward, backward)
    isempty(I) && throw(ArgumentError("no dependency path from $(repr(first(path))) to $(repr(last(path)))"))

    I, [v.name for v in [sourceinfo; targetinfo]]
end

selectiondependency(d::Dependency, selectors::AbstractVector; depth::Integer=1, direction=:both) = begin
    isempty(selectors) && throw(ArgumentError("at least one selector is required"))
    checkselection(depth, direction)
    selected = map(selectors) do selector
        if selector isa Symbol
            focusindices(d, selector; depth, direction)
        elseif selector isa Pair
            pathindices(d, selector)
        else
            throw(ArgumentError("selector must be a Symbol or Pair: $(repr(selector))"))
        end
    end
    I = phaseindices(d, Iterators.flatten(first.(selected)))
    focus = Set(Iterators.flatten(last.(selected)))
    g, J = Graphs.induced_subgraph(d.g, sort!(collect(union(I, configindices(d, I)))))
    N = d.N[J]
    Dependency(g, N, Dict(n => i for (i, n) in enumerate(N)), d.M, focus)
end

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
    error("no node found for $(v.name)")
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
        # self reference is handled within a single node
        if v0 == v
            continue
        elseif v0.state == :Bisect
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
        n1 = mainnode!(d, v)
        n2 = postnode!(d, v)
        link!(d, n1, n2)
        # needs `time` tags update, but equation args should be excluded due to cyclic dependency
        #HACK: support `when` tag while avoiding cyclic dependency
        #TODO: more elegant way to handle tags include/exclude
        link!(d, v, n1; equation=false, exclude=(:when,))
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
    C = Graphs.simplecycles(d.g)
    !isempty(C) && error("no cyclic dependency allowed: $([[d.N[i].info.name for i in c] for c in C])")
    J = Graphs.topological_sort_by_dfs(d.g)
    [d.N[i] for i in J]
end

label(n::VarNode; alias=false) = begin
    v = n.info
    name = alias && !isnothing(v.alias) ? v.alias : v.name
    name = string(name)
    tag = string(n.step)
    tag * name
end
labels(d::Dependency; alias=false, kw...) = label.(d.N; alias)

graphstyle(d::Dependency; rankdir=:TB, splines=:spline, kw...) = begin
    invoke(graphstyle, Tuple{Graph}, d; rankdir, splines, kw...)
end

stateattrs(s) = begin
    if s in (:Accumulate, :Capture, :Integrate, :Advance)
        (shape=:box, margin="0.09,0.05", penwidth=0.5)
    elseif s == :Drive
        (shape=:parallelogram, margin="0.01,0.00", penwidth=0.5)
    elseif s == :Provide
        (shape=:cylinder, labelloc=:b, margin="0.07,0.04", penwidth=0.5)
    elseif s == :Flag
        (shape=:diamond, penwidth=0.5)
    elseif s in (:Bisect, :Solve)
        (shape=:hexagon, penwidth=0.5)
    elseif s == :Produce
        (shape=:box, style=:rounded, peripheries=2, margin="0.09,0.05", penwidth=0.5)
    else
        (;)
    end
end

nodeattrs(d::Dependency; fontsize=9, alias=false, kw...) = begin
    Dict(i => begin
        n = d.N[i]
        v = n.info
        plain = istag(v, :context) || v.name in (:context, :config)
        a = plain ? (;) : stateattrs(v.state)
        phases = phasenodes(d, v)
        size = if length(phases) > 1 && v.state in (:Accumulate, :Capture, :Integrate, :Advance, :Produce)
            chars = maximum(textwidth(label(m; alias)) for m in phases)
            (width=round(chars * 0.6 * fontsize / 72 + 0.18; digits=3),
             height=round(1.4 * fontsize / 72 + 0.10; digits=3))
        else
            (;)
        end
        bold = v.name in d.focus
        italic = !plain && v.state in (:Hold, :Wrap, :Call, :Bring)
        text = bold || italic ? (label=graphlabel(label(n; alias); bold, italic),) : (;)
        stroke = n.step isa PreStep ? (style=haskey(a, :style) ? string(a.style, ",dashed") : "dashed",) : (;)
        merge(a, size, text, stroke)
    end for i in eachindex(d.N))
end

clusters(d::Dependency; group=:none, kw...) = begin
    group == :none && return Pair{String,Vector{Int}}[]
    group == :system || throw(ArgumentError("group must be :none or :system"))
    framework = (:System, :Context, :Clock, :Config, :Controller, :Calendar)
    groups = OrderedDict{Symbol,Vector{Int}}()
    for (i, n) in enumerate(d.N)
        s = n.info.system
        s in framework && continue
        push!(get!(Vector{Int}, groups, s), i)
    end
    [string(s) => I for (s, I) in groups]
end

edgeattrs(d::Dependency, a::Integer, b::Integer) = begin
    x, y = d.N[a], d.N[b]
    if x.info == y.info
        (arrowhead=:vee, penwidth=0.3, weight=4)
    elseif x.info.name == :config && istag(y.info, :parameter)
        (style=:dotted, arrowhead=:obox)
    elseif y.step isa PreStep
        (arrowhead=:onormal,)
    elseif x.info.system == y.info.system
        (weight=2,)
    else
        (;)
    end
end
edgeattrs(d::Dependency; kw...) = Dict(
    (src(e), dst(e)) => edgeattrs(d, src(e), dst(e)) for e in edges(d.g)
)

Base.show(io::IO, d::Dependency) = print(io, "Dependency")
Base.show(io::IO, ::MIME"text/plain", d::Dependency) = begin
    color = get(io, :color, false)
    VC = tokencolor(VarColor(); color)
    MC = tokencolor(MiscColor(); color)
    print(io, MC("Dependency update order: ["))
    print(io, join(VC.(label.(sort(d))), MC(", ")))
    print(io, MC("]"))
end
