@system Controller begin
    config ~ ::Cropbox.Config(override)
    context(config) ~ ::Cropbox.Context(context)
end

instance(S::Type{<:System}; config=(), options=()) = begin
    c = configure(config)
    #HACK: support placeholder (0) for the controller name
    c = configure(((k == Symbol(0) ? nameof(S) : k) => v for (k, v) in c)...)
    s = S(; config=c, options...)
    update!(s)
end

export Controller, instance
