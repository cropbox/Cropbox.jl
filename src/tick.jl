mutable struct Tick{T}
    t::T
end

advance!(tick::Tick{T}, t=one(T)) where T = (tick.t += t)
update!(tick::Tick{T}, t::T) where T = begin
    dt = t - tick.t
    dt > zero(T) && advance!(tick, dt)
    #TODO: make sure dt is not negative
    dt
end
update!(tick::Tick{T}, t) where T = update!(tick, convert(T, t))

import Base: convert, promote_rule, +
convert(::Type{Tick{T}}, tick::Tick) where T = tick
convert(::Type{T}, tick::Tick) where T = convert(T, tick.t)
# convert(::Type{Tick{T}}, t) where T = Tick(convert(T, t))
# promote_rule(::Type{Tick{T}}, ::Type{U}) where {T,U} = promote_type(T, U)
# +(tick::Tick, t) = +(promote(tick, t)...)

export Tick, update!
