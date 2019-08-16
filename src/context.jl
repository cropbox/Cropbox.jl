@system Clock begin
    self => self ~ ::System
    context ~ ::System(override)
    tick => nothing ~ advance
    tock => nothing ~ advance
    #unit
    start => 0 ~ track(time="tick") # parameter
    interval: i => 1 ~ track(time="tick") # parameter
    time(i) => i ~ accumulate::Int(init=0, time="tick")
    #start_datetime ~ parameter
    #datetime
end bare

advance!(c::Clock) = (advance!(c.tick); reset!(c.tock))
recite!(c::Clock) = advance!(c.tock)

import DataStructures: DefaultDict
const Queue = DefaultDict{Priority,Vector{Function}}

@system Context begin
    self => self ~ ::System
    context => self ~ ::System
    systems ~ ::[System]

    config => configure() ~ ::Config(override)
    queue => Queue(Vector{Function}) ~ ::Queue
    clock => Clock(; context=self) ~ ::Clock
end bare

option(c::Context, keys...) = option(c.config, keys...)

queue!(c::Context, f::Function, p::Priority) = push!(c.queue[p], f)
queue!(c::Context, f, p::Priority) = nothing
flush!(c::Context, cond) = begin
    q = filter(cond, c.queue)
    filter!(!cond, c.queue)
    foreach(f -> f(), q |> values |> Iterators.flatten)
end
preflush!(c::Context) = flush!(c, p -> p.first < 0)
postflush!(c::Context) = flush!(c, p -> p.first >= 0)

update!(c::Context) = begin
    # process pending operations from last timestep (i.e. produce)
    preflush!(c)

    # update state variables recursively
    update!(c.clock)
    foreach(update!, collect(c))

    # process pending operations from current timestep (i.e. flag, accumulate)
    postflush!(c)

    #TODO: process aggregate (i.e. transport) operations?
end

advance!(c::Context) = (advance!(c.clock); update!(c))
advance!(s::System) = advance!(s.context)

instance(SystemType::Type{S}, config=configure()) where {S<:System} = begin
    c = Context(; config=config)
    advance!(c)
    s = SystemType(; context=c)
    push!(c.systems, s)
    advance!(c)
    s
end

export update!, advance!, recite!, instance
