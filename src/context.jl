import DataStructures: DefaultDict
const Queue = DefaultDict{Priority,Vector{Function}}

@system Context begin
    self => self ~ ::System
    context => self ~ ::System
    systems ~ ::[System]

    config => configure() ~ ::Config(override)
    queue => Queue(Vector{Function}) ~ ::Queue
    clock => Clock(; context=self) ~ ::Clock
end

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
