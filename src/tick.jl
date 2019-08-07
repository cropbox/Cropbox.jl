mutable struct Tick{T} <: Real
    t::T
end

update!(tick::Tick, t::Tick) = begin
    dt = t - tick
    dt > 0 && (tick.t = t)
    #TODO: make sure dt is not negative
    dt
end
update!(tick::Tick, t) = update!(tick, convert(Tick, t))

import Base: convert, promote_rule, -
convert(::Type{Tick}, tick::Tick) = tick
convert(::Type{T}, tick::Tick) where {T <: Real} = convert(T, tick.t)
promote_rule(::Type{Tick{T}}, ::Type{U}) where {T,U<:Real} = promote_type(T, U)
-(a::Tick, b::Tick) = Tick(a.t - b.t)

export Tick, update!
