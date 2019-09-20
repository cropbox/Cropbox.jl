@system Context begin
    context ~ ::Nothing

    config ~ ::Config(override)
	order ~ ::Order
	queue ~ ::Queue

    clock(config) ~ ::Clock
end

option(c::Context, keys...) = option(c.config, keys...)

advance!(s::System, n=1) = begin
	c = s.context
    for i in 1:n
		preflush!(c.queue)
		S = collect!(c.order, s)
		update!.(S)
		postflush!(c.queue)
    end
	s
end

import DataFrames: DataFrame
run!(s::System, n=1; names...) = begin
	N = (t="context.clock.tick", names...)
	V = (k => [value(getproperty(s, n))] for (k, n) in pairs(N))
	df = DataFrame(; V...)
	for i in 2:n
		advance!(s)
		r = Tuple(value(getproperty(s, n)) for n in N)
		push!(df, r)
	end
	df
end

instance(S::Type{<:System}; config=configure()) = begin
    c = Context(; config=config)
    s = S(; context=c)
	#FIXME: better integration with Order?
	c.order.outdated = true
    advance!(s)
end

export advance!, run!, instance
