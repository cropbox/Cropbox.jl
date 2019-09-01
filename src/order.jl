extract(x::Var; equation=true, var=true) = begin
    eq = equation ? extract_equation(x, x.equation) : ()
    par = var ? extract_var(x) : ()
    [eq..., par...]
end
extract_equation(x::Var, e::StaticEquation) = Var[]
extract_equation(x::Var, e::DynamicEquation) = begin
    d = default(e)
    args = extract_equation(x, d, argsname(e))
    kwargs = extract_equation(x, d, kwargsname(e))
    [args..., kwargs...]
end
extract_equation(x::Var, d, n) = begin
    s = x.system
    resolve(a::Symbol) = begin
        interpret(v::Symbol) = (X = Set{Var}(); getvars(s, v, X); X)
        interpret(v::VarVal) = (X = Set{Var}(); getvars(v, X); X)
        interpret(v) = missing

        # default parameter values
        v = get(d, a, missing)
        !ismissing(v) && return interpret(v)

        # state vars from current system
        isdefined(s, a) && return interpret(a)

        # argument not found (partial function used by Call State)
        missing
    end
    l = Var[]
    for a in n
        v = resolve(a)
        #@show "$a -> $v"
        #@show "$(typeof(v))"
        !ismissing(v) && append!(l, v)
    end
    l
end
extract_var(x::Var) = filter!(!ismissing, getvar.(varfields(state(x))))

####

struct Node
    var::Var
    step::Step
end

prev(n::Node) = begin
    if n.step == MainStep()
        Node(n.var, PreStep())
    elseif n.step == PostStep()
        Node(n.var, MainStep())
    elseif n.step == PreStep()
        error("Pre-step node can't have a previous node: $n")
    end
end

# using LaTeXStrings
# label(n::Node) = begin
#     x = n.var
#     tag = begin
#         if n.step == PreStep()
#             "0"
#         elseif n.step == PostStep()
#             "1"
#         else
#             ""
#         end
#     end
#     latexstring("$(name(x))^{$(name(x.system))}_{$tag}")
# end

####

import DataStructures: DefaultOrderedDict
const Queue = DefaultOrderedDict{Int,Vector{Function}}
queue() = Queue(Vector{Function})

queue!(q::Queue, f::Function, i) = (push!(q[i], f))
flush!(q::Queue) = begin
    foreach(F -> foreach(f -> f(), F), values(q))
    empty!(q)
end
reset!(q::Queue, i) = filter!(p -> p[1] <= i, q)

####

import LightGraphs: DiGraph, add_vertex!, add_edge!, rem_edge!, topological_sort_by_dfs
mutable struct Order
    prequeue::Queue
    postqueue::Queue

    graph::DiGraph
    vars::Vector{Var}
    nodes::Vector{Node}
    indices::Dict{Node,Int}
    sortednodes::Vector{Node}
    sortedindices::Dict{Node,Int}
    order::Int

    Order() = begin
        o = new(queue(), queue())
        reset!(o)
    end
end

queue!(o::Order, f::Function, ::PrePriority, i) = queue!(o.prequeue, f, i)
queue!(o::Order, f::Function, ::PostPriority, i) = queue!(o.postqueue, f, i)
queue!(o::Order, f, p, i) = nothing
flush!(o::Order, ::PrePriority) = flush!(o.prequeue)
flush!(o::Order, ::PostPriority) = flush!(o.postqueue)
reset!(o::Order, i) = (reset!(o.prequeue, i); reset!(o.postqueue, i))

#FIXME: remove reset!
reset!(o::Order) = begin
    o.graph = DiGraph()
    o.vars = Var[]
    o.nodes = Node[]
    o.indices = Dict{Node,Int}()
    o.sortednodes = Node[]
    o.sortedindices = Dict{Node,Int}()
    o.order = 0
    o
end

index(o::Order, n::Node) = o.indices[n]
node(o::Order, i::Int) = o.nodes[i]

import Base: sort!
sort!(o::Order) = begin
    I = topological_sort_by_dfs(o.graph)
    @show I
    @show o.vars
    @show o.nodes
    o.sortednodes = [node(o, i) for i in I]
    o.sortedindices = Dict(n => i for (i, n) in enumerate(o.sortednodes))
end

node!(o::Order, v::Var, t::Step) = begin
    n = Node(v, t)
    #@show "node $n"
    if !haskey(o.indices, n)
        add_vertex!(o.graph)
        push!(o.vars, v)
        #@assert nv(g) == length(o.vars)
        i = length(o.vars)
        push!(o.nodes, n)
        o.indices[n] = i
        #@show "new node at $(o.indices[n])"
    end
    n
end
prenode!(o::Order, x::Var) = node!(o, x, PreStep())
mainnode!(o::Order, x::Var) = node!(o, x, MainStep())
postnode!(o::Order, x::Var) = node!(o, x, PostStep())
node!(o::Order, x::Var) = mainnode!(o, x)
node!(o::Order, x::Var{Solve}) = begin
    @show "innodes: Var{Solve} = $x"
    prenode!(o, x)
end
link!(o::Order, a::Node, b::Node) = begin
    @show "link: add edge $a ($(index(o, a))) => $b ($(index(o, b)))"
    add_edge!(o.graph, index(o, a), index(o, b))
end

innodes!(o::Order, x::Var; kwargs...) = begin # node!.(extract(x))
    @show "innodes $x"
    X = extract(x; kwargs...)
    @show "extracted = $X"
    [node!(o, x) for x in X]
end
inlink!(o::Order, x::Var, n1::Node; kwargs...) = begin
    for n0 in innodes!(o, x; kwargs...)
        link!(o, n0, n1)
    end
end

import Base: push!
push!(o::Order, x::Var) = begin
    n = mainnode!(o, x)
    inlink!(o, x, n)
end
push!(o::Order, x::Var{Accumulate}) = begin
    n0 = mainnode!(o, x)
    n1 = postnode!(o, x)
    link!(o, n0, n1)
    # Accumulate MainStep needs `time` update, but equation args should be excluded due to cyclic dependency
    inlink!(o, x, n0; equation=false)
    inlink!(o, x, n1)
end
push!(o::Order, x::Var{Capture}) = begin
    n0 = mainnode!(o, x)
    n1 = postnode!(o, x)
    link!(o, n0, n1)
    # Capture same as Accumulate
    inlink!(o, x, n0; equation=false)
    inlink!(o, x, n1)
end
push!(o::Order, x::Var{Solve}) = begin
    n0 = prenode!(o, x)
    n1 = mainnode!(o, x)
    link!(o, n0, n1)
    inlink!(o, x, n1)
end
push!(o::Order, x::Var{Flag}) = begin
    n0 = prenode!(o, x)
    n1 = postnode!(o, x)
    inlink!(o, x, n1)
end
push!(o::Order, x::Var{Produce}) = begin
    n0 = mainnode!(o, x)
    n1 = postnode!(o, x)
    inlink!(o, x, n0)
    inlink!(o, x, n1)
end

####

#using TikzGraphs, TikzPictures
collect!(o::Order, S) = begin
    L = collectvar(S)
    #TODO: incremental update
    reset!(o)
    X = [getvar(s, n) for (s, n) in L]
    for x in X
        push!(o, x)
    end
    # N = label.(o.nodes)
    # t = TikzGraphs.plot(o.graph, N)
    # TikzPictures.save(PDF("graph"), t)
    sort!(o)
end

update!(o::Order, s::System) = begin
    # process pending operations from last timestep (i.e. produce)
    flush!(o, PrePriority())

    # update state variables recursively
    S = collect(s)
    collect!(o, S)
    for (i, n) in enumerate(o.sortednodes)
        o.order = i
        update!(o, n)
    end

    # process pending operations from current timestep (i.e. flag, accumulate)
    flush!(o, PostPriority())

    #TODO: process aggregate (i.e. transport) operations?
    nothing
end

update!(o::Order, n::Node) = begin
    x = n.var
    t = n.step
    s = state(x)
    f = update!(s, x, t)
    p = priority(s)
    i = o.order
    queue!(o, f, p, i)
end

recite!(o::Order) = begin
    i1 = o.order
    @show "recite! to = $i1"
    n1 = o.sortednodes[i1]
    n0 = prev(n1)
    i0 = o.sortedindices[n0]
    @show "recite! from = $i0"
    reset!(o, i0)
    for i in (i0+1):(i1-1)
        n = o.sortednodes[i]
        @show "recite! $i -> $i1: $n"
        update!(o, n)
    end
end
