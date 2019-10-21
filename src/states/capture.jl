mutable struct Capture{V,T,R} <: State{V}
    value::V
    tick::T
    rate::R
end

Capture(; unit, time, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = unitfy(zero(_type), U)
    V = promote_type(V, typeof(v))
    t = value(time)
    T = typeof(t)
    TU = unittype(T)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    Capture{V,T,R}(v, t, zero(R))
end

@generated rateunit(s::Capture{V,T,R}) where {V,T,R} = unittype(R)
