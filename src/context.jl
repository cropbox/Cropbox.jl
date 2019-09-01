@system Context begin
    self => self ~ ::System
    context => self ~ ::System

    config => configure() ~ ::Config(override)
    order => Order() ~ ::Order

    clock => Clock(; context=self) ~ ::Clock
    systems ~ ::[System]
end

option(c::Context, keys...) = option(c.config, keys...)

update!(c::Context, skip::Bool=false) = update!(c.order, c)
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
