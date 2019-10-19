@system Context begin
    context ~ ::Nothing
    config ~ ::Config(extern)
	order ~ ::Order
	queue ~ ::Queue
    clock(config) ~ ::Clock
end

iscontext(::System) = false
iscontext(::Context) = true

update!(s::System, ::ContextPreStep) = preflush!(s.queue)
update!(s::System, ::ContextPostStep) = postflush!(s.queue)

# advance!(s::System, n=1) = begin
# 	c = s.context
#     for i in 1:n
# 		S = collect!(c.order, s)
# 		update!.(S)
#     end
# 	s
# end

advance!(s::System) = begin
	sc = s.context
	N = collect!(s)
	l = length(N)
	i = 1
	I = Int[]
	while i <= l
		n = N[i]
		@show (i, n)
		if n.step == ContextPreStep()
			push!(I, i)
		end
		update!(n)
		i += 1
		if n.step == ContextPostStep()
			i0 = pop!(I)
			c = n.info
			if c != sc && !isnothing(sc) && value(c.clock.tick) < value(sc.clock.tick)
				i = i0
			end
		end
	end
	s
end
advance!(s::System, n) = begin
	for i in 1:n
		advance!(s)
	end
end

# advance!(n::SystemNode) = advance!(n, n.step)
# advance!(n::SystemNode, ::ContextPreStep) = begin
# 	s = n.info
# 	c = s.context
# 	I = if s != c && !isnothing(c)
# 		(value(c.clock.tick) - value(s.clock.tick)) / value(s.clock.step) |> upreferred
# 	else
# 		1
# 	end
# 	for i in 1:I
# 		update!(n)
# 	end
# end

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

instance(S::Type{<:System}; config=configure(), kwargs...) = begin
    s = S(; config=config, kwargs...)
    advance!(s)
end

export advance!, run!, instance
