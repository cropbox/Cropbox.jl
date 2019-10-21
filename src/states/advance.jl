mutable struct Advance{T} <: State{T}
    value::Timepiece{T}
end

Advance(; init=nothing, step=nothing, unit, _type, _...) = begin
    T = valuetype(_type, value(unit))
    t = isnothing(init) ? zero(T) : value(init)
    dt = isnothing(step) ? oneunit(T) : value(step)
    T = promote_type(typeof(t), typeof(dt))
    Advance{T}(Timepiece{T}(t, dt))
end

value(s::Advance) = s.value.t
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)
