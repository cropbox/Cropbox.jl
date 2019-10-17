using LightGraphs

abstract type OrderStep end
struct SystemStep <: OrderStep end
struct ContextPreStep <: OrderStep end
struct ContextPostStep <: OrderStep end

const SystemNode = Node{System,OrderStep}

update!(s::SystemNode) = update!(s.info, s.step)
update!(s::System, ::SystemStep) = update!(s)

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

node!(o::Order, s::System, t::OrderStep) = vertex!(o, SystemNode(s, t))
node!(o::Order, s) = node!(o, s, SystemStep())

link!(g::Order, a::SystemNode, b::SystemNode) = begin
    #@show "add edge $a ($(g.I[a])) -> $b ($(g.I[b]))"
    add_edge!(g.g, g.I[a], g.I[b])
end
link!(g::Order, a, b, c) = (link!(g, a, b); link!(g, b, c))

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
    ns = node!(o, s)
    if iscontext(d)
        c0 = node!(o, d, ContextPreStep())
        c1 = node!(o, d)
        c2 = node!(o, d, ContextPostStep())
        link!(o, c0, c1, c2)
        link!(o, c0, ns)
        link!(o, c1, ns)
        link!(o, ns, c2)
    else
        nd = node!(o, d)
        link!(o, nd, ns)
    end
    d ∉ o.S && visit!(o, d)
end

collect!(o::Order, s::System) = begin
    if o.outdated
        visit!(o, s)
        J = topological_sort_by_dfs(o.g)
        o.systems = [o.V[i] for i in J]
        o.outdated = false
    end
    o.systems
end
