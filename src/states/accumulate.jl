mutable struct Accumulate{V,T,R} <: State{V}
    value::V
    tick::T
    rate::R
end

Accumulate(; unit, time, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = isnothing(_value) ? unitfy(zero(_type), U) : _value
    V = promote_type(V, typeof(v))
    t = value(time)
    T = typeof(t)
    TU = unittype(T)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    Accumulate{V,T,R}(v, t, zero(R))
end

@generated rateunit(::Accumulate{V,T,R}) where {V,T,R} = unittype(R)
