mutable struct Timepiece{T<:Number}
    t::T
    dt::T
end

Timepiece{T}(t) where {T<:Number} = Timepiece{T}(t, oneunit(T))

advance!(timer::Timepiece{T}, t) where {T<:Number} = (timer.t += t; timer.t)
advance!(timer::Timepiece{T}) where {T<:Number} = advance!(timer, timer.dt)

import Base: convert, promote_rule, +
convert(::Type{Timepiece{T}}, timer::Timepiece) where {T<:Number} = timer
convert(::Type{T}, timer::Timepiece) where {T<:Number} = convert(T, timer.t)
# convert(::Type{Timepiece{T}}, t) where T = Timepiece(convert(T, t))
# promote_rule(::Type{Timepiece{T}}, ::Type{U}) where {T,U} = promote_type(T, U)
# +(timer::Timepiece, t) = +(promote(timer, t)...)
