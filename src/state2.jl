abstract type State{V} end

value(v) = v
value(s::State{V}) where V = s.value::V

store!(s::State, v) = (s.value = unitfy(v, unit(s)); nothing)

import Base: getindex, length, iterate
getindex(s::State, i) = s
length(s::State) = 1
iterate(s::State) = (s, nothing)
iterate(s::State, i) = nothing

# default(V::Type{<:Number}) = zero(V)
# default(V::Type) = V()

import Unitful: unit
unit(::State{V}) where V = unittype(V)
unittype(V) = ((V <: Quantity) ? unit(V) : nothing)

import Unitful: Units, dimension
valuetype(::State{V}) where V = V
valuetype(T, ::Nothing) = T
valuetype(T, U::Units) = Quantity{T, dimension(U), typeof(U)}
valuetype(::Type{Array{T,N}}, U::Units) where {T,N} = Array{valuetype(T, U), N}

# #HACK: state var referred by `time` tag must have been already declared
# timeunittype(time::String, s::System) = unit(state(getvar(s, time)))
# timetype(T, time::String, s::System) = valuetype(T, timeunittype(time, s))
# timevalue(t::String, s::System) = begin
#     x = getvar(s, t)
#     #FIXME: ensure only access static values on init
#     @assert typeof(x.equation) <: StaticEquation
#     v = value(x.equation)
#     u = timeunittype(t, s)
#     unitfy(v, u)
# end
# timevalue(t, _) = t
#
rateunittype(U::Nothing, T::Units) = T^-1
rateunittype(U::Units, T::Units) = U/T
rateunittype(U::Units, T::Nothing) = U
rateunittype(U::Nothing, T::Nothing) = nothing

abstract type Priority end
struct PrePriority <: Priority end
struct PostPriority <: Priority end

priority(::S) where {S<:State} = priority(S)
priority(::Type{<:State}) = PostPriority()

import Base: show
show(io::IO, s::S) where {S<:State} = begin
    r = repr(value(s))
    r = length(r) > 40 ? "<..>" : r
    print(io, r)
end

####

mutable struct Pass{V} <: State{V}
    value::V
end

Pass(; unit, _value, _type=nothing, _...) = begin
    v = unitfy(_value, value(unit))
    V = typeof(v)
    Pass{V}(v)
end

####

mutable struct Advance{T} <: State{T}
    value::Timepiece{T}
end

Advance(; init=nothing, step=nothing, unit, _type=Int64, _...) = begin
    T = valuetype(_type, value(unit))
    t = isnothing(init) ? zero(T) : value(init)
    dt = isnothing(step) ? oneunit(T) : value(step)
    T = promote_type(typeof(t), typeof(dt))
    Advance{T}(Timepiece{T}(t, dt))
end

value(s::Advance) = s.value.t
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)

####

mutable struct Preserve{V} <: State{V}
    value::Union{V,Missing}
end

# Preserve is the only State that can store value `nothing`
Preserve(; unit, _value, _type=nothing, _...) = begin
    @show _value
    @show unit
    @show value(unit)
    v = unitfy(_value, value(unit))
    V = typeof(v)
    Preserve{V}(v)
end

####

mutable struct Track{V} <: State{V}
    value::V
end

Track(; unit, _value, _type=Float64, _...) = begin
    U = value(unit)
    #V = valuetype(_type, u)
    v = unitfy(_value, U)
    #V = promote_type(V, typeof(v))
    V = typeof(v)
    #T = typeof(value(time))
    Track{V}(v)
end

####

mutable struct Drive{V,T} <: State{V}
    value::V
    key::Symbol
end

Drive(; key=nothing, unit, _name, _value, _type=Float64, _...) = begin
    k = isnothing(key) ? _name : Symbol(key)
    #V = valuetype(_type, value(unit))
    V = typeof(_value)
    #T = typeof(value(time))
    Drive{V}(_value, k)
end

####

mutable struct Call{V,F<:Function} <: State{V}
    value::F
end

Call(; unit, _value, _type=Float64, _...) = begin
    V = valuetype(_type, value(unit))
    F = typeof(_value)
    Call{V,F}(_value)
end

value(s::Call{V,F}) where {V,F} = s.value::F
#HACK: showing s.value could trigger StackOverflowError
show(io::IO, s::Call) = print(io, "<call>")

####

mutable struct Accumulate{V,T,R} <: State{V}
    value::V
    time::State{T}
    tick::T
    rate::R
end

Accumulate(; unit, time, _value, _type=Float64, _...) = begin
    U = value(unit)
    #V = valuetype(_type, U)
    isnothing(_value) && (_value = zero(_type))
    V = typeof(_value)
    #TU = timeunittype(time, _system)
    #T = valuetype(_type_time, TU)
    #T = timetype(_type_time, time, _system)
    t = value(time)
    T = typeof(t)
    TU = unittype(T)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    Accumulate{V,T,R}(_value, time, t, zero(R))
end

@generated rateunit(::Accumulate{V,T,R}) where {V,T,R} = unittype(R)

####

mutable struct Capture{V,T,R} <: State{V}
    value::V
    time::State{T}
    tick::T
    rate::R
end

Capture(; unit, time, _value, _type=Float64, _...) = begin
    U = value(unit)
    #V = valuetype(_type, U)
    #TU = timeunittype(time, _system)
    #T = valuetype(_type_time, TU)
    t = value(time)
    T = typeof(t)
    TU = unittype(T)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    Capture{V,T,R}(zero(V), time, t, zero(R))
end

@generated rateunit(s::Capture{V,T,R}) where {V,T,R} = unittype(R)

####

mutable struct Flag{Bool} <: State{Bool}
    value::Bool
end

Flag(; _value, _type=Bool, _...) = begin
    V = typeof(_value)
    Flag{V}(_value)
end

####

mutable struct Produce{S<:System} <: State{S}
    value::Vector{S}
    context::System
    name::Symbol # used in recurisve collecting in getvar!
end

struct Product{S<:System}
    type::Type{S}
    args
end
iterate(p::Product) = (p, nothing)

Produce(; _name, _system, _type::Type{S}=System, _...) where {S<:System} = begin
    Produce{S}(S[], _system.context, _name)
end

value(s::Produce{S}) where {S<:System} = s.value::Vector{S}
produce(s::Type{<:System}; args...) = Product(s, args)

# produce(s::Produce, p::Product, x::AbstractVar) = begin
#     c = s.context
#     k = p.type(; context=c, p.args...)
#     append!(s.value, k)
#     inform!(c.order, x, k)
# end
# produce(s::Produce, p::Vector{<:Product}, x::AbstractVar) = produce.(Ref(s), p, Ref(x))
# produce(s::Produce, ::Nothing, x::AbstractVar) = nothing
# update!(s::Produce, f::AbstractVar, ::MainStep) = nothing
# update!(s::Produce, f::AbstractVar, ::PostStep) = (p = f(); () -> produce(s, p, f))

unit(s::Produce) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
priority(::Type{<:Produce}) = PrePriority()

####

mutable struct Solve{V,T} <: State{V}
    value::V
    lower::Union{State{V},V,Nothing}
    upper::Union{State{V},V,Nothing}
    context::System
end

#TODO: reimplement Solve
Solve(; lower=nothing, upper=nothing, unit, _system, _type=Float64, _...) = begin
    V = valuetype(_type, value(unit))
    Solve{V,T}(zero(V), lower, upper, _system.context)
end

using Roots
# update!(s::Solve, f::AbstractVar, ::PreStep) = nothing
# update!(s::Solve, f::AbstractVar, ::MainStep) = begin
#     #@show "begin solve $s"
#     trigger(x) = (store!(s, x); recite!(s.context.order, f))
#     cost(e) = x -> (trigger(x); e(x) |> ustrip)
#     b = (value(s.lower), value(s.upper))
#     if nothing in b
#         try
#             c = cost(x -> (x - f())^2)
#             v = find_zero(c, value(s))
#         catch e
#             #@show "convergence failed: $e"
#             v = value(s)
#         end
#     else
#         c = cost(x -> (x - f()))
#         v = find_zero(c, b, Roots.AlefeldPotraShi())
#     end
#     #HACK: trigger update with final value
#     trigger(v)
#     recitend!(s.context.order, f)
# end

export produce
