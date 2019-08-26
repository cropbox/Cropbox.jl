abstract type State{V} end

check!(s::State) = true
value(s::State{V}) where V = s.value::V
store!(s::State, f::AbstractVar) = store!(s, f())
store!(s::State, v) = (s.value = unitfy(v, unit(s)); nothing)

checktime!(s::State) = check!(s.time)
checkprob!(s::State) = (p = value!(s.prob); (p >= 1 || rand() <= p))

import Base: getindex, length, iterate
getindex(s::State, i) = s
length(s::State) = 1
iterate(s::State) = (s, nothing)
iterate(s::State, i) = nothing

default(V::Type{<:Number}) = V(0)
default(V::Type) = V()

import Unitful: unit
unit(s::State) = nothing

unittype(::Nothing, _) = nothing
unittype(U::Unitful.Units, _) = U
unittype(unit::String, s::System) = value!(s, unit)

valuetype(::State{V}) where V = V
valuetype(T, ::Nothing) = T
valuetype(T, U::Unitful.Units) = Quantity{T, dimension(U), typeof(U)}
valuetype(::Type{Array{T,N}}, U::Unitful.Units) where {T,N} = Array{valuetype(T, U), N}

#HACK: state var referred by `time` tag must have been already declared
timeunittype(time::String, s::System) = unit(state(getvar(s, time)))
timetype(T, time::String, s::System) = valuetype(T, timeunittype(time, s))
timevalue(t::String, s::System) = value!(s, t)
timevalue(t, _) = t

rateunittype(U::Nothing, TU::Unitful.Units) = TU^-1
rateunittype(U::Unitful.Units, TU::Unitful.Units) = U/TU
rateunittype(U::Unitful.Units, TU::Nothing) = U
rateunittype(U::Nothing, TU::Nothing) = nothing

const Priority = Int
priority(s::State) = 0

import Base: show
show(io::IO, s::State) = print(io, "$(repr(value(s)))")

####

mutable struct Pass{V,U} <: State{V}
    value::V
end

Pass(; unit=nothing, _name, _system, _value=missing, _type=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    if ismissing(_value)
        v = default(V)
    else
        v = unitfy(_value, U)
        V = promote_type(V, typeof(v))
    end
    N = Symbol("$(name(_system))<$_name>")
    Pass{V,U}(v)
end

unit(::Pass{V,U}) where {V,U} = U

####

mutable struct Advance{T,U} <: State{T}
    value::Timepiece{T}
end

Advance(; init=nothing, step=nothing, unit=nothing, _name, _system, _type=Int64, _...) = begin
    U = unittype(unit, _system)
    T = valuetype(_type, U)
    t = isnothing(init) ? zero(T) : timevalue(init, _system)
    dt = isnothing(step) ? oneunit(T) : timevalue(step, _system)
    T = promote_type(typeof(t), typeof(dt))
    N = Symbol("$(name(_system))<$_name>")
    Advance{T,U}(Timepiece{T}(t, dt))
end

check!(s::Advance) = false
value(s::Advance) = s.value.t
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)
unit(::Advance{T,U}) where {T,U} = U

####

mutable struct Preserve{V,U} <: State{V}
    value::Union{V,Missing}
end

# Preserve is the only State that can store value `nothing`
Preserve(; unit=nothing, _name, _system, _value=missing, _type=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    if ismissing(_value)
        v = missing
    else
        v = unitfy(_value, U)
        V = promote_type(V, typeof(v))
    end
    N = Symbol("$(name(_system))<$_name>")
    Preserve{V,U}(v)
end

check!(s::Preserve) = ismissing(s.value)
value(s::Preserve{V}) where V = s.value::Union{V,Missing}
unit(::Preserve{V,U}) where {V,U} = U

####

mutable struct Track{V,T,U} <: State{V}
    value::V
    time::TimeState{T}
end

Track(; unit=nothing, time="context.clock.tick", _name, _system, _value=missing, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    if ismissing(_value)
        v = default(V)
    else
        v = unitfy(_value, U)
        V = promote_type(V, typeof(v))
    end
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Track{V,T,U}(v, TimeState{T}(_system, time))
end

check!(s::Track) = checktime!(s)
unit(::Track{V,T,U}) where {V,T,U} = U

####

mutable struct Drive{V,T,U} <: State{V}
    key::Symbol
    value::V
    time::TimeState{T}
end

Drive(; key=nothing, unit=nothing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    k = isnothing(key) ? _name : Symbol(key)
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Drive{V,T,U}(k, default(V), TimeState{T}(_system, time))
end

check!(s::Drive) = checktime!(s)
store!(s::Drive, f::AbstractVar) = store!(s, value!(f()[s.key])) # value!() for Var
unit(::Drive{V,T,U}) where {V,T,U} = U

####

mutable struct Call{V,T,U} <: State{V}
    value::Union{Function,Missing}
    time::TimeState{T}
end

Call(; unit=nothing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Call{V,T,U}(missing, TimeState{T}(_system, time))
end

check!(s::Call) = checktime!(s)
value(s::Call{V}) where {V} = s.value::Union{V,Function}
store!(s::Call, f::AbstractVar) = begin
    s.value = (a...; k...) -> unitfy(f()(a...; k...), unit(s))
    #HACK: no function should be returned for queueing
    nothing
end
unit(::Call{V,T,U}) where {V,T,U} = U
#HACK: showing s.value could trigger StackOverflowError
show(io::IO, s::Call) = print(io, "<call>")

####

import DataStructures: OrderedDict

mutable struct Accumulate{V,T,R,U,RU} <: State{V}
    init::VarVal{V}
    time::TimeState{T}
    tick::Union{T,Missing}
    rate::R
    value::V
end

Accumulate(; init=0, unit=nothing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    TU = timeunittype(time, _system)
    T = valuetype(_type_time, TU)
    #T = timetype(_type_time, time, _system)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    N = Symbol("$(name(_system))<$_name>")
    Accumulate{V,T,R,U,RU}(VarVal{V}(_system, init), TimeState{T}(_system, time), missing, default(R), default(V))
end

check!(s::Accumulate) = checktime!(s)
store!(s::Accumulate, f::AbstractVar) = begin
    t = s.time.ticker.t
    t0 = s.tick
    if ismissing(t0)
        v = value!(s.init)
    else
        v = s.value + s.rate * (t - t0)
    end
    store!(s, v)
    r = unitfy(f(), rateunit(s))
    () -> (s.tick = t; s.rate = r)
end
#TODO special handling of no return value for Accumulate/Capture?
#store!(s::Accumulate, ::Nothing) = store!(s, () -> 0)
unit(::Accumulate{V,T,R,U,RU}) where {V,T,R,U,RU} = U
rateunit(::Accumulate{V,T,R,U,RU}) where {V,T,R,U,RU} = RU
priority(s::Accumulate) = 2

####

mutable struct Capture{V,T,R,U,RU} <: State{V}
    time::TimeState{T}
    tick::Union{T,Missing}
    rate::R
    value::V
end

Capture(; unit=nothing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    TU = timeunittype(time, _system)
    T = valuetype(_type_time, TU)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    N = Symbol("$(name(_system))<$_name>")
    Capture{V,T,R,U,RU}(TimeState{T}(_system, time), missing, default(R), default(V))
end

check!(s::Capture) = checktime!(s)
store!(s::Capture, f::AbstractVar) = begin
    t = s.time.ticker.t
    t0 = s.tick
    if !ismissing(t0)
        v = s.rate * (t - t0)
        store!(s, v)
    end
    r = unitfy(f(), rateunit(s))
    () -> (s.tick = t; s.rate = r)
end
#TODO special handling of no return value for Accumulate/Capture?
#store!(s::Capture, ::Nothing) = store!(s, () -> 0)
unit(s::Capture{V,T,R,U,RU}) where {V,T,R,U,RU} = U
rateunit(s::Capture{V,T,R,U,RU}) where {V,T,R,U,RU} = RU
priority(s::Capture) = 2

####

mutable struct Flag{Bool,P,T} <: State{Bool}
    value::Bool
    prob::VarVal{P}
    time::TimeState{T}
end

Flag(; prob=1, time="context.clock.tick", _name, _system, _type=Bool, _type_prob=Float64, _type_time=Float64, _...) = begin
    V = _type
    P = _type_prob
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Flag{V,P,T}(zero(V), VarVal{P}(_system, prob), TimeState{T}(_system, time))
end

check!(s::Flag) = checktime!(s) && checkprob!(s)
store!(s::Flag, f::AbstractVar) = (v = f(); () -> store!(s, v))
priority(s::Flag) = 1

####

mutable struct Produce{S<:System,T} <: State{S}
    system::System
    value::Vector{S}
    time::TimeState{T}
    name::Symbol # used in recurisve collecting in getvar!
end

struct Product{S<:System,A}
    type::Type{S}
    args::A
end

Produce(; time="context.clock.tick", _name, _system, _type::Type{S}=System, _type_time=Float64, _...) where {S<:System} = begin
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Produce{S,T}(_system, S[], TimeState{T}(_system, time), _name)
end

check!(s::Produce) = checktime!(s)
value(s::Produce{S}) where {S<:System} = s.value::Vector{S}
produce(s::Type{<:System}; args...) = Product(s, args)
produce(s::Produce, p::Product) = append!(s.value, p.type(; context=s.system.context, p.args...))
produce(s::Produce, p::Vector{<:Product}) = produce.(Ref(s), p)
produce(s::Produce, ::Nothing) = nothing
store!(s::Produce, f::AbstractVar) = (p = f(); () -> produce(s, p))
store!(s::Produce, ::Nothing) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
priority(s::Produce) = -1

####

mutable struct Solve{V,T,U} <: State{V}
    value::V
    time::TimeState{T}
    lower::Union{VarVal{V},Nothing}
    upper::Union{VarVal{V},Nothing}
    context::System
    solving::Bool
end

Solve(; lower=nothing, upper=nothing, unit=nothing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Solve{V,T,U}(default(V), TimeState{T}(_system, time), VarVal{V}(_system, lower), VarVal{V}(_system, upper), _system.context, false)
end

check!(s::Solve) = checktime!(s) && !s.solving
using Roots
store!(s::Solve, f::AbstractVar) = begin
    s.solving = true
    cost(x) = (store!(s, x); recite!(s.context); y = f(); y)
    b = (value!(s.lower), value!(s.upper))
    if nothing in b
        v = find_zero(cost, value(s))
    else
        v = find_zero(cost, b)
    end
    #FIXME: ensure all state vars are updated once and only once (i.e. no duplice produce)
    #HACK: trigger update with final value
    store!(s, v); recite!(s.context); update!(s.context)
    s.solving = false
    store!(s, v)
end
unit(::Solve{V,T,U}) where {V,T,U} = U

export produce
