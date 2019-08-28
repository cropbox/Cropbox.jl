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

@system Context begin
    self => self ~ ::System
    context => self ~ ::System

    config => configure() ~ ::Config(override)
    queue => Queue(Vector{Function}) ~ ::Queue
    index => 0 ~ ::Int
    recite_index => 0 ~ ::Int

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

update!(c::Context) = begin
    # process pending operations from last timestep (i.e. produce)
    preflush!(c)

    # update state variables recursively
    S = collect(c)
    l = collectvar(S)
    for i in 1:length(l)
        c.index = i
        #(s, n) = l[i] # DefaultDict version
        ((s, n), p) = l[i] # PriorityQueue version
        value!(s, n)
    end
    while c.recite_index > 0
        r = c.recite_index-1
        c.recite_index = 0
        for i in 1:r
            c.index = i
            #(s, n) = l[i] # DefaultDict version
            ((s, n), p) = l[i] # PriorityQueue version
            value!(s, n)
        end
    end

    # process pending operations from current timestep (i.e. flag, accumulate)
    postflush!(c)

    #TODO: process aggregate (i.e. transport) operations?
    nothing
end

advance!(c::Context) = (advance!(c.clock); update!(c))
advance!(s::System) = advance!(s.context)
recite!(c::Context) = begin
    dequeue!(c)
    recite!(c.clock)
    #@show "recite! $(c.clock.tock) index = $(c.recite_index) => $(c.index)"
    c.recite_index = c.index
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

export update!, advance!, recite!, instance
