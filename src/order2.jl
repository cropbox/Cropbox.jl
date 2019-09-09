mutable struct Order
    systems::Vector{System}
    outdated::Bool
end

Order() = Order(System[], true)

inform!(o::Order) = (o.outdated = true)
collect!(o::Order, s::System) = begin
    if o.outdated
        o.systems = collect!(s)
        o.outdated = false
    end
    o.systems
end

using LightGraphs
collect!(s::System; recursive=true) = begin
    g = DiGraph()
    V = System[]
    I = Dict{System,Int}()
    S = Set{System}()
    visit(s::System) = begin
        @show "visit $s"
        add(d::System) = begin
            i = get(I, d, nothing)
            if isnothing(i)
                add_vertex!(g)
                push!(V, d)
                i = I[d] = length(V)
            end
            i
        end
        add(s)

        link(d::System) = begin
            (s == d) && return
            add(d)
            @show "add edge $s ($(I[s])) -> $d ($(I[d]))"
            add_edge!(g, I[s], I[d])
        end
        #HACK: use VarInfo tags to figure out dependency
        vars = Dict(i.name => i for i in VarInfo.(source(s).args))
        D = System[]
        for n in collectible(s)
            if !get(vars[n].tags, :override, false)
                append!(D, getfield(s, n))
            end
        end
        @show "collectible $D"
        foreach(link, D)

        push!(S, s)
        filter!(d -> d ∉ S, D)
        @show "collectible filtered $D"
        recursive && foreach(visit, D)
    end
    visit(s) = visit.(s)
    visit(s)
    J = topological_sort_by_dfs(g)
    [V[i] for i in reverse(J)]
end
