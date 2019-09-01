@system Context begin
    self => self ~ ::System
    context => self ~ ::System

    config => configure() ~ ::Config(override)
    order => Order() ~ ::Order

    clock => Clock(; context=self) ~ ::Clock
    systems ~ ::[System]
end

option(c::Context, keys...) = option(c.config, keys...)

update!(c::Context) = update!(c.order, c)
advance!(c::Context, n=1) = begin
    for i in 1:n
        advance!(c.clock)
        update!(c)
    end
end
advance!(s::System, n=1) = advance!(s.context, n)

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
