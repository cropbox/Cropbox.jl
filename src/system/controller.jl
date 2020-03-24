@system Controller begin
    config ~ ::Cropbox.Config(override)
    context(config) ~ ::Cropbox.Context(context)
end

instance(S::Type{<:System}; config=(), kwargs...) = begin
    c = configure(config)
    #HACK: support placeholder (0) for the controller name
    c = Config((k == Symbol(0) ? nameof(S) : k) => v for (k, v) in c)
    s = S(; config=c, kwargs...)
    update!(s)
end

export Controller, instance
