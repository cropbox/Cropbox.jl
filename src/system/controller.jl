@system Controller begin
    config ~ ::Cropbox.Config(override)
    context(config) ~ ::Cropbox.Context(context)
end

instance(S::Type{<:System}; config=(), kwargs...) = begin
    s = S(; config=configure(config), kwargs...)
    #update!(s)
end

export Controller, instance
