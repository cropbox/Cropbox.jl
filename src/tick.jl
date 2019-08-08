mutable struct Tick{T} <: Real
    t::T
end

update!(tick::Tick{T}, t::T) where T = begin
    dt = t - tick.t
    dt > 0 && (tick.t = t)
    #TODO: make sure dt is not negative
    dt
end
update!(tick::Tick{T}, t) where T = update!(tick, convert(T, t))

import Base: convert, promote_rule, -
convert(::Type{Tick}, tick::Tick) = tick
convert(::Type{T}, tick::Tick) where {T <: Real} = convert(T, tick.t)
promote_rule(::Type{Tick{T}}, ::Type{U}) where {T,U<:Real} = promote_type(T, U)

export Tick, update!
