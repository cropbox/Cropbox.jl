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

using LaTeXStrings
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
using TikzGraphs, TikzPictures
save(d::Dependency, name) = TikzPictures.save(PDF(String(name)), TikzGraphs.plot(d.g, label.(d.V)))

####

extract(i::VarInfo; equation=true, tag=true) = begin
    parse(v::Expr) = begin
        f(v) = begin
            @show v
            a = v.args[1]
            @show a
            isexpr(a) ? f(a) : isexpr(v, :., :ref) ? a : nothing
        end
        f(v)
    end
    parse(v::Symbol) = v
    parse(v) = nothing
    pick(a) = @capture(a, k_=v_) ? parse(v) : parse(a)
    pack(A) = filter(!isnothing, pick.(A)) |> Tuple
    eq = equation ? pack(i.args) : ()
    @show eq
    #HACK: exclude internal tags (i.e. _type)
    tags = filter(!isnothing, [parse(p[2]) for p in i.tags if !startswith(String(p[1]), "_")]) |> Tuple
    par = tag ? tags : ()
    @show par
    Set([eq..., par...]) |> collect
end

####

node!(d::Dependency{VarNode}, v::VarInfo, t::Step) = vertex!(d, VarNode(v, t))
prenode!(d::Dependency{VarNode}, v) = node!(d, v, PreStep())
mainnode!(d::Dependency{VarNode}, v) = node!(d, v, MainStep())
postnode!(d::Dependency{VarNode}, v) = node!(d, v, PostStep())
node!(d::Dependency{VarNode}, v::VarInfo) = begin
    if v.state == :Solve
        @show "innodes: Var{<:Solve} = $v"
        prenode!(d, v)
    else
        mainnode!(d, v)
    end
end
invertices!(d::Dependency{VarNode}, v::VarInfo; kwargs...) = begin
    @show "innodes $v"
    A = extract(v; kwargs...)
    @show "extracted = $A"
    f(a::Symbol) = f(d.M[a])
    f(v0::VarInfo) = begin
        @show v0
        if v0 == v
            @show "cyclic! prenode $v"
            prenode!(d, v0)
        else
            node!(d, v0)
        end
    end
    f.(A)
end

add!(d::Dependency{VarNode}, v::VarInfo) = begin
    @show "add! $v"
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
    elseif v.state == :Flag
        n0 = mainnode!(d, v)
        n1 = postnode!(d, v)
        inlink!(d, v, n1)
    elseif v.state == :Produce
        n0 = mainnode!(d, v)
        n1 = postnode!(d, v)
        inlink!(d, v, n0)
        inlink!(d, v, n1)
    else
        n = mainnode!(d, v)
        inlink!(d, v, n)
    end
end
