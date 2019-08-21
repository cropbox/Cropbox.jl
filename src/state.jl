abstract type State end

check!(s::State) = true
value(s::State) = s.value
store!(s::State, f::Function) = store!(s, f())
store!(s::State, v) = (s.value = unitfy(v, unit(s)))
store!(s::State, ::Nothing) = nothing

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
unit(s::State) = missing

unittype(::Missing, _) = missing
unittype(U::Unitful.Units, _) = U
unittype(unit::String, s::System) = value!(s, unit)

valuetype(T, ::Missing) = T
valuetype(T, U::Unitful.Units) = Quantity{T, dimension(U), typeof(U)}

#HACK: state var referred by `time` tag must have been already declared
timeunittype(time::String, s::System) = unit(getvar(s, time).state)
timetype(T, time::String, s::System) = valuetype(T, timeunittype(time, s))
timevalue(t::String, s::System) = value!(s, t)
timevalue(t, _) = t

rateunittype(U::Missing, TU::Unitful.Units) = TU^-1
rateunittype(U::Unitful.Units, TU::Unitful.Units) = U/TU
rateunittype(U::Unitful.Units, TU::Missing) = U
rateunittype(U::Missing, TU::Missing) = missing

const Priority = Int
priority(s::State) = 0

import Base: show
show(io::IO, s::State) = print(io, "$(repr(value(s)))")

####

mutable struct Pass{V,U} <: State
    value::V
end

Pass(; unit=missing, _value=nothing, _type=Float64, _system, _...) = begin
    U = unittype(unit, _system)
    if isnothing(_value)
        V = valuetype(_type, U)
        v = default(V)
    else
        v = unitfy(_value, U)
        V = typeof(v)
    end
    Pass{V,U}(v)
end

unit(::Pass{V,U}) where {V,U} = U

####

mutable struct Advance{T,U} <: State
    value::Timepiece{T}
end

Advance(; init=nothing, step=nothing, unit=missing, _type=Int64, _system, _...) = begin
    U = unittype(unit, _system)
    T = valuetype(_type, U)
    t = isnothing(init) ? zero(T) : timevalue(init, _system)
    dt = isnothing(step) ? oneunit(T) : timevalue(step, _system)
    T = promote_type(typeof(t), typeof(dt))
    Advance{T,U}(Timepiece{T}(t, dt))
end

check!(s::Advance) = false
value(s::Advance) = s.value.t
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)
unit(::Advance{T,U}) where {T,U} = U

####

mutable struct Preserve{V,U} <: State
    value::Union{V,Missing}
end

Preserve(; unit=missing, _value=nothing, _type=Float64, _system, _...) = begin
    U = unittype(unit, _system)
    if isnothing(_value)
        V = valuetype(_type, U)
        v = missing
    else
        v = unitfy(_value, U)
        V = typeof(v)
    end
    Preserve{V,U}(v)
end

check!(s::Preserve) = ismissing(s.value)
unit(::Preserve{V,U}) where {V,U} = U

####

mutable struct Track{V,T,U} <: State
    value::V
    time::TimeState{T}
end

Track(; unit=missing, time="context.clock.tick", _system, _value=nothing, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    if isnothing(_value)
        V = valuetype(_type, U)
        v = default(V)
    else
        v = unitfy(_value, U)
        V = typeof(v)
    end
    T = timetype(_type_time, time, _system)
    Track{V,T,U}(v, TimeState{T}(_system, time))
end

check!(s::Track) = checktime!(s)
unit(::Track{V,T,U}) where {V,T,U} = U

####

mutable struct Drive{V,T,U} <: State
    key::Symbol
    value::V
    time::TimeState{T}
end

Drive(; key=nothing, unit=missing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    k = isnothing(key) ? _name : Symbol(key)
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    Drive{V,T,U}(k, default(V), TimeState{T}(_system, time))
end

check!(s::Drive) = checktime!(s)
store!(s::Drive, f::Function) = store!(s, f()[s.key])
unit(::Drive{V,T,U}) where {V,T,U} = U

####

mutable struct Call{V,T,U} <: State
    value::Function
    time::TimeState{T}
end

Call(; unit=missing, time="context.clock.tick", _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    Call{V,T,U}(() -> default(V), TimeState{T}(_system, time))
end

check!(s::Call) = checktime!(s)
store!(s::Call, f::Function) = begin
    s.value = (a...; k...) -> unitfy(f()(a...; k...), unit(s))
    #HACK: no function should be returned for queueing
    nothing
end
unit(::Call{V,T,U}) where {V,T,U} = U
#HACK: showing s.value could trigger StackOverflowError
show(io::IO, s::Call) = print(io, "<call>")

####

import DataStructures: OrderedDict

mutable struct Accumulate{V,R,T,U} <: State
    init::VarVal{V}
    time::TimeState{T}
    rates::OrderedDict{T,R}
    value::V
    cache::OrderedDict{T,V}
end

Accumulate(; init=0, unit=missing, time="context.clock.tick", _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    TU = timeunittype(time, _system)
    T = valuetype(_type_time, TU)
    #T = timetype(_type_time, time, _system)
    R = valuetype(_type, rateunittype(U, TU))
    Accumulate{V,R,T,U}(VarVal{V}(_system, init), TimeState{T}(_system, time), OrderedDict{T,R}(), default(V), OrderedDict{T,V}())
end

check!(s::Accumulate) = checktime!(s)
store!(s::Accumulate, f::Function) = begin
    v = value!(s.init)
    R = s.rates
    T0 = collect(keys(R))
    for t in reverse(T0)
        if haskey(s.cache, t)
            v = s.cache[t]
            R = filter(p -> p.first >= t, R)
            T0 = collect(keys(R))
            break
        end
    end
    t = s.time.ticker.t
    T1 = [T0; t]; T1 = T1[2:end]
    v += sum((T1 - T0) .* values(R))
    s.cache[t] = store!(s, v)
    r = f()
    () -> (s.rates[t] = r) # s.cache = filter(p -> p.first == t, s.cache)
end
unit(::Accumulate{V,R,T,U}) where {V,R,T,U} = U
priority(s::Accumulate) = 2

####

# Difference can be actually Track
# mutable struct Difference{V,T} <: State end

####

mutable struct Flag{P,T} <: State
    value::Bool
    prob::VarVal{P}
    time::TimeState{T}
end

Flag(; prob=1, time="context.clock.tick", _system, _type=Bool, _type_prob=Float64, _type_time=Float64, _...) = begin
    V = _type
    P = _type_prob
    T = timetype(_type_time, time, _system)
    Flag(zero(V), VarVal{P}(_system, prob), TimeState{T}(_system, time))
end

check!(s::Flag) = checktime!(s) && checkprob!(s)
store!(s::Flag, f::Function) = (v = f(); () -> store!(s, v))
priority(s::Flag) = 1

####

mutable struct Produce{S<:System,T} <: State
    system::System
    value::Vector{S}
    time::TimeState{T}
end

struct Product{S<:System,K,V}
    type::Type{S}
    args::Vector{Pair{K,V}}
end

Produce(; time="context.clock.tick", _system, _type::Type{S}=System, _type_time=Float64, _...) where {S<:System} = begin
    T = timetype(_type_time, time, _system)
    Produce{S,T}(_system, S[], TimeState{T}(_system, time))
end

check!(s::Produce) = checktime!(s)
produce(s::Type{S}; args...) where {S<:System} = Product(s, collect(args))
produce(s::Produce, p::Product) = append!(s.value, p.type(; context=s.system.context, p.args...))
produce(s::Produce, p::Vector{Product}) = produce.(s, p)
produce(s::Produce, ::Nothing) = nothing
store!(s::Produce, f::Function) = (p = f(); () -> produce(s, p))
getindex(s::Produce, i) = getindex(s.value, i)
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
priority(s::Produce) = -1

####

mutable struct Solve{V,T,U} <: State
    value::V
    time::TimeState{T}
    lower::Union{VarVal{V},Nothing}
    upper::Union{VarVal{V},Nothing}
    clock::System
    solving::Bool
end

Solve(; lower=nothing, upper=nothing, unit=missing, time="context.clock.tick", _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    Solve{V,T,U}(default(V), TimeState{T}(_system, time), VarVal{V}(_system, lower), VarVal{V}(_system, upper), _system.context.clock, false)
end

check!(s::Solve) = checktime!(s) && !s.solving
using Roots
store!(s::Solve, f::Function) = begin
    s.solving = true
    cost(x) = (store!(s, x); recite!(s.clock); y = f(); y)
    b = (value!(s.lower), value!(s.upper))
    if nothing in b
        v = find_zero(cost, value(s))
    else
        v = find_zero(cost, b)
    end
    #FIXME: no longer needed with regime?
    #HACK: trigger update with final value
    cost(v)
    s.solving = false
    store!(s, v)
end
unit(::Solve{V,T,U}) where {V,T,U} = U

export produce
