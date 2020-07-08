import Random

@system Controller begin
    config ~ ::Cropbox.Config(override)
    context(config) ~ ::Cropbox.Context(context)
end

instance(S::Type{<:System}; config=(), options=(), seed=nothing) = begin
    !isnothing(seed) && Random.seed!(seed)
    c = configure(config)
    #HACK: support placeholder (0) for the controller name
    c = configure(((k == Symbol(0) ? namefor(S) : k) => v for (k, v) in c)...)
    s = S(; config=c, options...)
    update!(s)
end

export Controller, instance
