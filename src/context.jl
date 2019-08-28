import DataStructures: DefaultDict
const Queue = DefaultDict{Int,Vector{Function}}

queue!(q::Queue, f::Function, o) = push!(q[o], f)
dequeue!(q::Queue) = empty!(q)
flush!(q::Queue, cond) = begin
    for (o, l) in filter(p -> cond(p[1]), q)
        foreach(f -> f(), l)
        empty!(l)
    end
end

####

mutable struct Index
    current::Int
    recital::Int
end

update!(x::Index, i) = (x.current = i)
recite!(x::Index) = begin
    #@show "recite! index = $(x.recital) => $(x.current - 1)"
    x.recital = x.current - 1
end
recital!(x::Index) = begin
    r = 0
    if x.recital > 0
        r = x.recital
        x.recital = 0
    end
    r
end

####

@system Context begin
    self => self ~ ::System
    context => self ~ ::System

    config => configure() ~ ::Config(override)
    queue => Queue(Vector{Function}) ~ ::Queue
    index => Index(0, 0) ~ ::Index

    clock => Clock(; context=self) ~ ::Clock
    systems ~ ::[System]
end

option(c::Context, keys...) = option(c.config, keys...)

queue!(c::Context, f::Function, o) = queue!(c.queue, f, o)
queue!(c::Context, f, o) = nothing
dequeue!(c::Context) = empty!(c.queue)
flush!(c::Context, cond) = flush!(c.queue, cond)
preflush!(c::Context) = flush!(c, o -> o < 0)
postflush!(c::Context) = flush!(c, o -> o > 0)

using LightGraphs
#using TikzGraphs, TikzPictures
import DataStructures: OrderedDict
collectvar_dp(S::AbstractSet, _) = begin
    L = collectvar_pq(S, p -> true)
    g = SimpleDiGraph(length(L))

    extract(x::Var, s::System) = begin
        eq = extract_eq(x, s, x.equation)
        par = extract_par(x)
        [eq..., par...]
    end
    extract_eq(x::Var, s::System, e::StaticEquation) = Var[]
    extract_eq(x::Var, s::System, e::DynamicEquation) = begin
        d = default(e)
        args = extract_eq(x, s, d, argsname(e))
        kwargs = extract_eq(x, s, d, kwargsname(e))
        [args..., kwargs...]
    end
    extract_eq(x::Var, s::System, d, n) = begin
        resolve(a::Symbol) = begin
            interpret(v::Symbol) = getvar(s, v)
            interpret(v::VarVal) = getvar(v)
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
            !ismissing(v) && push!(l, v)
        end
        l
    end
    extract_par(x::Var{S}) where {S<:State} = getvar.(varfields(state(x)))

    X = [(s, getvar(s, n)) for (s, n) in L]
    I = Dict(v[2] => k for (k, v) in enumerate(X))
    for (s, x) in X
        d = extract(x, s)
        for v in d
            ismissing(v) && continue
            add_edge!(g, I[v], I[x])
        end
    end
    # N = ["$(name(s))<$(name(x))>" for (s, x) in X]
    # t = TikzGraphs.plot(g, N)
    # TikzPictures.save(PDF("graph"), t)
    g
end

update!(c::Context, skip::Bool=false) = begin
    # process pending operations from last timestep (i.e. produce)
    preflush!(c)

    # update state variables recursively
    S = collect(c)
    l = collectvar(S, skip)
    update!(c, l)

    # process pending operations from current timestep (i.e. flag, accumulate)
    postflush!(c)

    #TODO: process aggregate (i.e. transport) operations?
    nothing
end
update!(c::Context, l) = begin
    for i in 1:length(l)
        update!(c, l, i)
    end
    while 0 < (r = recital!(c.index))
        for i in 1:r
            update!(c, l, i)
        end
    end
end
update!(c::Context, l, i) = begin
    update!(c.index, i)
    (s, n) = l[i]
    value!(s, n)
end

advance!(c::Context, skip::Bool) = (advance!(c.clock); update!(c, skip))
advance!(c::Context, n=1) = begin
    for i in 1:n-1
        advance!(c, true)
    end
    advance!(c, false)
end
advance!(s::System, n=1) = advance!(s.context, n)
recite!(c::Context) = begin
    dequeue!(c)
    recite!(c.clock)
    recite!(c.index)
end

instance(Ss::Type{<:System}...; config=configure()) = begin
    c = Context(; config=config)
    advance!(c)
    for S in Ss
        s = S(; context=c)
        push!(c.systems, s)
    end
    advance!(c)
    c.systems[1]
end

export advance!, instance
