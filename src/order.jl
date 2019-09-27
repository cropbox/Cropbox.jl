using LightGraphs

mutable struct Order
    systems::Vector{System}
    outdated::Bool
    g::DiGraph
    V::Vector{System}
    I::Dict{System,Int}
    S::Set{System}
end

Order() = Order(System[], true, DiGraph(), System[], Dict{System,Int}(), Set{System}())

add!(o::Order, s::System) = begin
    i = get(o.I, s, nothing)
    if isnothing(i)
        add_vertex!(o.g)
        push!(o.V, s)
        i = o.I[s] = length(o.V)
    end
    i
end

link!(o::Order, s::System, d::System) = begin
    (s == d) && return
    add!(o, d)
    #@show "add edge $s ($(o.I[s])) -> $d ($(o.I[d]))"
    add_edge!(o.g, o.I[s], o.I[d])
end

visit!(o::Order, s::System) = begin
    #@show "visit $s"
    add!(o, s)

    D = System[]
    F = fieldnamesextern(s)
    for n in collectible(s)
        (n in F) && append!(D, getfield(s, n))
    end
    #@show "collectible $D"
    for d in D
        link!(o, s, d)
    end

    push!(o.S, s)
    filter!(d -> d ∉ o.S, D)
    #@show "collectible filtered $D"
    for d in D
        visit!(o, d)
    end
end

visit!(o::Order, s::System, d::System) = begin
    #@show "visit $s -> $d"
    #add!(o, s)
    #@assert haskey(o.I, s)
    link!(o, s, d)
    #push!(o.S, s)
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
