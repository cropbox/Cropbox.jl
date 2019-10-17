using LightGraphs

abstract type SystemStep end
struct RegularStep <: SystemStep end
struct BeginStep <: SystemStep end
struct EndStep <: SystemStep end

const SystemNode = Node{System,SystemStep}

update!(s::SystemNode) = update!(s.info)

mutable struct Order
    systems::Vector{SystemNode}
    outdated::Bool
    g::DiGraph
    V::Vector{SystemNode}
    I::Dict{SystemNode,Int}
    S::Set{System}
end

Order() = Order(SystemNode[], true, DiGraph(), SystemNode[], Dict{SystemNode,Int}(), Set{System}())

vertex!(g::Order, n::SystemNode) = begin
    if !haskey(g.I, n)
        add_vertex!(g.g)
        push!(g.V, n)
        g.I[n] = length(g.V)
    end
    n
end

node!(o::Order, s::System, t::SystemStep) = vertex!(o, SystemNode(s, t))
regularnode!(o::Order, s) = node!(o, s, RegularStep())
beginnode!(o::Order, s) = node!(o, s, BeginStep())
endnode!(o::Order, s) = node!(o, s, EndStep())

link!(g::Order, a::SystemNode, b::SystemNode) = begin
    #@show "add edge $a ($(g.I[a])) -> $b ($(g.I[b]))"
    add_edge!(g.g, g.I[a], g.I[b])
end

visit!(o::Order, s::System) = begin
    #@show "visit $s"
    push!(o.S, s)
    F = fieldnamesextern(s)
    for c in collectible(s)
        if c in F
            d = getfield(s, c)
            visit!(o, s, d)
        end
    end
end

visit!(o::Order, s::System, d::System) = begin
    #@show "visit $s -> $d"
    a = regularnode!(o, s)
    b = regularnode!(o, d)
    link!(o, a, b)
    d ∉ o.S && visit!(o, d)
end

collect!(o::Order, s::System) = begin
    if o.outdated
        visit!(o, s)
        J = topological_sort_by_dfs(o.g)
        o.systems = [o.V[i] for i in reverse(J)]
        o.outdated = false
    end
    o.systems
end
