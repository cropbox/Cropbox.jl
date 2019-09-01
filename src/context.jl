@system Context begin
    self => self ~ ::System
    context => self ~ ::System

    config => configure() ~ ::Config(override)
    order => Order() ~ ::Order

    clock => Clock(; context=self) ~ ::Clock
    systems ~ ::[System]
end

option(c::Context, keys...) = option(c.config, keys...)

update!(c::Context, skip::Bool=false) = begin
    # process pending operations from last timestep (i.e. produce)
    preflush!(c.order)

    # update state variables recursively
    S = collect(c)
    update!(c.order, S)

    # process pending operations from current timestep (i.e. flag, accumulate)
    postflush!(c.order)

    #TODO: process aggregate (i.e. transport) operations?
    nothing
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
