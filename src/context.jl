@system Context begin
    self => self ~ ::System
    context => self ~ ::System

    config => configure() ~ ::Config(override)
    order => Order() ~ ::Order

    clock => Clock(; context=self) ~ ::Clock
    systems ~ ::[System]
end

option(c::Context, keys...) = option(c.config, keys...)

update!(c::Context, reset) = begin
    if reset
        update!(c.order, true, collectvar(collect(c)))
    else
        update!(c.order, false)
    end
end
advance!(c::Context, n=1, reset=false) = begin
    for i in 1:n
        advance!(c.clock)
        update!(c, reset)
    end
end
advance!(s::System, n=1) = advance!(s.context, n)

instance(Ss::Type{<:System}...; config=configure()) = begin
    c = Context(; config=config)
    advance!(c, 1, true)
    for S in Ss
        s = S(; context=c)
        push!(c.systems, s)
    end
    #FIXME: avoid redundant reset
    advance!(c, 1, true)
    c.systems[1]
end

export advance!, instance
