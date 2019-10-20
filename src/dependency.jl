using LightGraphs

struct Dependency
    g::DiGraph
    V::Vector{VarNode}
    I::Dict{VarNode,Int}
    M::Dict{Symbol,VarInfo}
end

Dependency(M::Dict{Symbol,VarInfo}) = Dependency(DiGraph(), VarNode[], Dict{VarNode,VarInfo}(), M)

vertex!(d::Dependency, v::VarNode) = begin
    if !haskey(d.I, v)
        add_vertex!(d.g)
        push!(d.V, v)
        d.I[v] = length(d.V)
        #@show "new vertex at $(d.I[v])"
    end
    v
end

node!(d::Dependency, v::VarInfo, t::VarStep) = vertex!(d, VarNode(v, t))
node!(d::Dependency, v::Symbol, t::VarStep) = vertex!(d, VarNode(d.M[v], t))
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

invertices!(d::Dependency, v::VarInfo; kwargs...) = begin
    #@show "innodes $v"
    A = extract(v; kwargs...)
    #@show "extracted = $A"
    f(a::Symbol) = f(d.M[a])
    f(v0::VarInfo) = begin
        #@show v0
        if v0 == v || v0.state == :Solve
            prenode!(d, v0)
        else
            mainnode!(d, v0)
        end
    end
    f.(A)
end

extract(v::VarInfo; equation=true, tag=true) = begin
    parse(v::Expr) = begin
        f(v) = begin
            #@show v
            a = v.args[1]
            #@show a
            isexpr(a) ? f(a) : isexpr(v, :., :ref) ? a : nothing
        end
        f(v)
    end
    parse(v::Symbol) = v
    parse(v) = nothing
    pick(a) = let k, v; @capture(a, k_=v_) ? parse(v) : parse(a) end
    pack(A) = filter(!isnothing, pick.(A)) |> Tuple
    eq = equation ? pack(v.args) : ()
    #@show eq
    #HACK: exclude internal tags (i.e. _type)
    tags = filter(!isnothing, [parse(p[2]) for p in v.tags if !startswith(String(p[1]), "_")]) |> Tuple
    par = tag ? tags : ()
    #@show par
    Set([eq..., par...]) |> collect
end

inlink!(d::Dependency, v, v1::VarNode; kwargs...) = begin
    #@show "inlink! v = $v to v1 = $v1"
    for v0 in invertices!(d, v; kwargs...)
        link!(d, v0, v1)
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
        inlink!(d, v, n0; equation=false)
        inlink!(d, v, n2)
    elseif v.state == :Capture
        n0 = mainnode!(d, v)
        n1 = postnode!(d, v)
        link!(d, n0, n1)
        inlink!(d, v, n0; equation=false)
        inlink!(d, v, n1)
    elseif v.state == :Solve
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        link!(d, n0, n1)
        inlink!(d, v, n1)
        # needs access to context in Solve constructor
        c = mainnode!(d, :context)
        link!(d, c, n0)
    elseif v.state == :Flag
        n0 = mainnode!(d, v)
        n1 = postnode!(d, v)
        link!(d, n0, n1)
        inlink!(d, v, n1)
    elseif v.state == :Produce
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        n2 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, n1, n2)
        inlink!(d, v, n1)
        inlink!(d, v, n2)
        # needs access to context in Produce constructor
        c = mainnode!(d, :context)
        link!(d, c, n0)
    elseif isnothing(v.state) && istag(v, :context)
        n0 = prenode!(d, v)
        n1 = mainnode!(d, v)
        n2 = postnode!(d, v)
        link!(d, n0, n1)
        link!(d, n1, n2)
        inlink!(d, v, n1)
    else
        n = mainnode!(d, v)
        inlink!(d, v, n)
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
    [d.V[i] for i in J]
end

#using LaTeXStrings
label(n::VarNode) = begin
    v = n.info
    name = replace(String(isempty(v.alias) ? v.name : v.alias[1]), "_" => "")
    tag = begin
        if n.step == PreStep()
            "0"
        elseif n.step == PostStep()
            "1"
        else
            ""
        end
    end
    latexstring("$(name)_{$tag}")
end
#using TikzGraphs, TikzPictures
#save(d::Dependency, name) = TikzPictures.save(PDF(String(name)), TikzGraphs.plot(d.g, label.(d.V)))
save(d::Dependency, name) = nothing
