mutable struct Timepiece{T<:Number}
    t::T
    dt::T
end

Timepiece{T}(t) where {T<:Number} = Timepiece{T}(t, oneunit(T))

advance!(timer::Timepiece{T}, t) where {T<:Number} = (timer.t += t; timer.t)
advance!(timer::Timepiece{T}) where {T<:Number} = advance!(timer, timer.dt)

Base.convert(::Type{Timepiece{T}}, timer::Timepiece) where {T<:Number} = timer
Base.convert(::Type{T}, timer::Timepiece) where {T<:Number} = convert(T, timer.t)
# Base.convert(::Type{Timepiece{T}}, t) where T = Timepiece(convert(T, t))
# Base.promote_rule(::Type{Timepiece{T}}, ::Type{U}) where {T,U} = promote_type(T, U)
# Base.+(timer::Timepiece, t) = +(promote(timer, t)...)
