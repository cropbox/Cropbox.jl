extract(x::Var; equation=true, var=true) = begin
    eq = equation ? extract_equation(x, x.equation) : ()
    par = var ? extract_var(x) : ()
    [eq..., par...]
end
extract_equation(x::Var, e::StaticEquation) = Var[]
extract_equation(x::Var, e::DynamicEquation) = begin
    d = e.default
    args = extract_equation(x, d, e.args.names)
    kwargs = extract_equation(x, d, e.kwargs.names)
    [args..., kwargs...]
end
extract_equation(x::Var, d, n) = begin
    s = x.system
    resolve(a::Symbol) = begin
        interpret(v::Symbol) = (X = Set{Var}(); getvars(s, v, X); X)
        interpret(v::VarVal) = (X = Set{Var}(); getvars(v, X); X)
        interpret(v::Var) = Set{Var}([v])
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
#     s = "$(name(x))^{$(name(x.system))}_{$tag}"
#     s = replace(s, "_" => "-")
#     latexstring(s)
# end

####

import DataStructures: DefaultOrderedDict
#HACK: Any seems to be faster than Function
const Queue = DefaultOrderedDict{Int,Vector{Any}}
queue() = Queue(Vector{Any})

queue!(q::Queue, f::Function, i) = (push!(q[i], f))
flush!(q::Queue) = begin
    foreach(F -> foreach(f -> f(), F), values(q))
    empty!(q)
end
reset!(q::Queue, i) = filter!(p -> p[1] < i, q)

####

import LightGraphs: DiGraph, add_vertex!, add_edge!, rem_edge!, topological_sort_by_dfs
mutable struct Order
    prequeue::Queue
    postqueue::Queue

    graph::DiGraph
    vars::Vector{Var}
    updatedvars::Set{Var}
    updatedsystems::Set{System}
    nodes::Vector{Node}
    indices::Dict{Node,Int}
    sortednodes::Vector{Node}
    sortedindices::Dict{Node,Int}
    order::Int
    recites::Dict{Var,Vector{Node}}
    recitends::Dict{Var,Vector{Node}}

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
    o.updatedvars = Set{Var}()
    o.updatedsystems = Set{System}()
    o.nodes = Node[]
    o.indices = Dict{Node,Int}()
    o.sortednodes = Node[]
    o.sortedindices = Dict{Node,Int}()
    o.order = 0
    o.recites = Dict{Var,Vector{Node}}()
    o.recitends = Dict{Var,Vector{Node}}()
    o
end

index(o::Order, n::Node) = o.indices[n]
node(o::Order, i::Int) = o.nodes[i]

import Base: sort!
import LightGraphs: simplecycles
sort!(o::Order) = begin
    #@assert isempty(simplecycles(o.graph))
    #@show simplecycles(o.graph)
    # for cy in simplecycles(o.graph)
    #     for i in cy
    #         n = node(o, i)
    #         @show n
    #     end
    # end
    I = topological_sort_by_dfs(o.graph)
    #@show I
    #@show o.vars
    #@show o.nodes
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
    #@show "innodes: Var{Solve} = $x"
    prenode!(o, x)
end
link!(o::Order, a::Node, b::Node) = begin
    #@show "link: add edge $a ($(index(o, a))) => $b ($(index(o, b)))"
    add_edge!(o.graph, index(o, a), index(o, b))
end

innodes!(o::Order, x::Var; kwargs...) = begin # node!.(extract(x))
    #@show "innodes $x"
    X = extract(x; kwargs...)
    #@show "extracted = $X"
    node(x0) = begin
        if x == x0
            #@show "cyclic! prenode $x0"
            prenode!(o, x0)
        else
            node!(o, x0)
        end
    end
    [node(x) for x in X]
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

import Base: broadcastable
broadcastable(o::Order) = Ref(o)

#using TikzGraphs, TikzPictures
collect!(o::Order, X, reset::Bool) = begin
    #TODO: incremental update
    reset && reset!(o)
    #@show "collect! $X"
    if !isempty(X)
        push!.(o, X)
        # N = label.(o.nodes)
        # @show N
        # t = TikzGraphs.plot(o.graph, N)
        # TikzPictures.save(PDF("graph"), t)
        sort!(o)
    end
end

update!(o::Order, reset=false, X=Set{Var}()) = begin
    # process pending operations from last timestep (i.e. produce)
    flush!(o, PrePriority())

    # update state variables recursively
    if reset
        #@show "update! reset"
        collect!(o, X, true)
    else
        #@show "update! incremental"
        #@show o.updatedvars
        #@show o.updatedsystems
        S = collect.(o.updatedsystems) |> Iterators.flatten
        #@show S
        X = union(X, o.updatedvars, collectvar.(S)...)
        collect!(o, X, false)
        empty!(o.updatedvars)
        empty!(o.updatedsystems)
    end

    # ensure all state vars are updated once and only once (i.e. no duplice produce)
    for (i, n) in enumerate(o.sortednodes)
        o.order = i
        update!(o, n)
        #@show "updated! $n"
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

import LightGraphs: bfs_tree, edges
recite!(o::Order, x::Var) = begin
    if haskey(o.recites, x)
        NX = o.recites[x]
        #@show "recite! reuse $(length(NX)) for $x"
        n0 = NX[1]
        i0 = o.sortedindices[n0]
        #@show "recite! from = $i0 ($n0)"
        reset!(o, i0)
    else
        # i1 = o.order
        # n1 = o.sortednodes[i1]
        #HACK: assume recite! called from MainStep
        n1 = Node(x, MainStep())
        i1 = o.sortedindices[n1]
        #@show i1 == o.order
        #@show "recite! to = $i1 ($n1)"
        n0 = prev(n1)
        i0 = o.sortedindices[n0]
        #@show "recite! from = $i0 ($n0)"
        reset!(o, i0)

        E = bfs_tree(o.graph, index(o, n1); dir=:in) |> edges
        #@show E |> collect
        V = Set([(e.src, e.dst) for e in E] |> Iterators.flatten)
        #@show V
        N1 = o.sortednodes[i0:i1-1]
        #@show N1
        N2 = node.(o, V)
        #@show N2
        #@show length(N1)
        #@show length(N2)
        NX = intersect(N1, N2)
        NXR = setdiff(N1, NX)
        #@show NX
        #@show NXR
        #@show length(NX)
        #@show length(NXR)
        # for i in (i0+1):(i1-1)
        #     n = o.sortednodes[i]
        o.recites[x] = NX
        o.recitends[x] = NXR
    end
    for n in NX
        i = o.sortedindices[n]
        update!(o, n)
        #@show "recited! $i: $(name(n.var))"
    end
end
recitend!(o::Order, x::Var) = begin
    NX = o.recitends[x]
    for n in NX
        i = o.sortedindices[n]
        update!(o, n)
        #@show "recitend! $i: $(name(n.var))"
    end
end

inform!(o::Order, x::Var, s::System) = begin
    #@show "inform $x => $s"
    push!(o.updatedvars, x)
    push!(o.updatedsystems, s)
end
