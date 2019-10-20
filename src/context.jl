@system Context begin
    context ~ ::Nothing
    config ~ ::Config(override)
	queue ~ ::Queue
    clock(config) ~ ::Clock
end

import DataFrames: DataFrame
run!(s::System, n=1; names...) = begin
	N = (t="context.clock.tick", names...)
	V = (k => [value(getproperty(s, n))] for (k, n) in pairs(N))
	df = DataFrame(; V...)
	for i in 2:n
		update!(s)
		r = Tuple(value(getproperty(s, n)) for n in N)
		push!(df, r)
	end
	df
end

export run!
