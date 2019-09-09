@system Context begin
    self => self ~ ::System(expose)
    context => self ~ ::System

    config => configure() ~ ::Config(override, expose)
	order => Order() ~ ::Order
	queue => Queue() ~ ::Queue

    clock(config) => Clock(; config=config) ~ ::Clock
    systems ~ ::[System]
end

option(c::Context, keys...) = option(c.config, keys...)

advance!(c::Context, n=1) = begin
    for i in 1:n
		preflush!(c.queue)
		S = collect!(c.order, c)
		for s in S
        	updatestatic!(s)
		end
		postflush!(c.queue)
    end
end
advance!(s::System, n=1) = advance!(s.context, n)

import DataFrames: DataFrame
run!(s::System, n=1; names...) = begin
	N = (t="context.clock.tick", names...)
	V = (k => [value(getproperty(s, n))] for (k, n) in pairs(N))
	df = DataFrame(; V...)
	for i in 1:n
		advance!(s)
		r = Tuple(value(getproperty(s, n)) for n in N)
		push!(df, r)
	end
	df
end

instance(Ss::Type{<:System}...; config=configure()) = begin
    c = Context(; config=config)
    advance!(c, 1)
    for S in Ss
        s = S(; context=c)
        push!(c.systems, s)
		#FIXME: better integration with Order?
		c.order.outdated = true
    end
    #FIXME: avoid redundant reset
    advance!(c, 1)
    c.systems[1]
end

export advance!, run!, instance
