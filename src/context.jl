@system Context begin
    self => self ~ ::System
    context => self ~ ::System
    systems ~ ::[System]

    config => configure() ~ ::Config(override)
    prequeue => Function[] ~ ::Vector{Function}
    postqueue => Function[] ~ ::Vector{Function}
    clock => Clock(; context=self) ~ ::Clock
end

option(c::Context, keys...) = option(c.config, keys...)

queue!(c::Context, f::Function, p::Priority) = begin
    q = (p >= 0) ? c.postqueue : c.prequeue
    push!(q, f)
end
queue!(c::Context, f, p::Priority) = nothing
dequeue!(c::Context) = (empty!(c.prequeue); empty!(c.postqueue))
flush!(q::Vector{Function}) = begin
    foreach(f -> f(), q)
    empty!(q)
end
preflush!(c::Context) = flush!(c.prequeue)
postflush!(c::Context) = flush!(c.postqueue)

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
recite!(c::Context) = (dequeue!(c); recite!(c.clock))

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
