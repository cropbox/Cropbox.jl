abstract type State{V} end

check!(s::State) = true
value(s::State{V}) where V = s.value::V
store!(s::State, f::Function) = store!(s, f())
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
unit(s::State) = missing

unittype(::Missing, _) = missing
unittype(U::Unitful.Units, _) = U
unittype(unit::String, s::System) = value!(s, unit)

valuetype(::State{V}) where V = V
valuetype(T, ::Missing) = T
valuetype(T, U::Unitful.Units) = Quantity{T, dimension(U), typeof(U)}
valuetype(::Type{Array{T,N}}, U::Unitful.Units) where {T,N} = Array{valuetype(T, U), N}

#HACK: state var referred by `time` tag must have been already declared
timeunittype(time::String, s::System) = unit(state(getvar(s, time)))
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

mutable struct Pass{V,U,N} <: State{V}
    value::V
end

Pass(; unit=missing, _name, _system, _value=missing, _type=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    if ismissing(_value)
        v = default(V)
    else
        v = unitfy(_value, U)
        V = promote_type(V, typeof(v))
    end
    N = Symbol("$(name(_system))<$_name>")
    Pass{V,U,N}(v)
end

unit(::Pass{V,U,N}) where {V,U,N} = U

####

mutable struct Advance{T,U,N} <: State{T}
    value::Timepiece{T}
end

Advance(; init=nothing, step=nothing, unit=missing, _name, _system, _type=Int64, _...) = begin
    U = unittype(unit, _system)
    T = valuetype(_type, U)
    t = isnothing(init) ? zero(T) : timevalue(init, _system)
    dt = isnothing(step) ? oneunit(T) : timevalue(step, _system)
    T = promote_type(typeof(t), typeof(dt))
    N = Symbol("$(name(_system))<$_name>")
    Advance{T,U,N}(Timepiece{T}(t, dt))
end

check!(s::Advance) = false
value(s::Advance) = s.value.t
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)
unit(::Advance{T,U,N}) where {T,U,N} = U

####

mutable struct Preserve{V,U,N} <: State{V}
    value::Union{V,Missing}
end

# Preserve is the only State that can store value `nothing`
Preserve(; unit=missing, _name, _system, _value=missing, _type=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    if ismissing(_value)
        v = missing
    else
        v = unitfy(_value, U)
        V = promote_type(V, typeof(v))
    end
    N = Symbol("$(name(_system))<$_name>")
    Preserve{V,U,N}(v)
end

check!(s::Preserve) = ismissing(s.value)
value(s::Preserve{V}) where V = s.value::Union{V,Missing}
unit(::Preserve{V,U,N}) where {V,U,N} = U

####

mutable struct Track{V,T,U,N} <: State{V}
    value::V
    time::TimeState{T}
end

Track(; unit=missing, time="context.clock.tick", _name, _system, _value=missing, _type=Float64, _type_time=Float64, _...) = begin
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
    Track{V,T,U,N}(v, TimeState{T}(_system, time))
end

check!(s::Track) = checktime!(s)
unit(::Track{V,T,U,N}) where {V,T,U,N} = U

####

mutable struct Drive{V,T,U,N} <: State{V}
    key::Symbol
    value::V
    time::TimeState{T}
end

Drive(; key=nothing, unit=missing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    k = isnothing(key) ? _name : Symbol(key)
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Drive{V,T,U,N}(k, default(V), TimeState{T}(_system, time))
end

check!(s::Drive) = checktime!(s)
store!(s::Drive, f::Function) = store!(s, f()[s.key])
unit(::Drive{V,T,U,N}) where {V,T,U,N} = U

####

mutable struct Call{V,T,U,N} <: State{V}
    value::Union{Function,Missing}
    time::TimeState{T}
end

Call(; unit=missing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Call{V,T,U,N}(missing, TimeState{T}(_system, time))
end

check!(s::Call) = checktime!(s)
value(s::Call{V}) where {V} = s.value::Union{V,Function}
store!(s::Call, f::Function) = begin
    s.value = (a...; k...) -> unitfy(f()(a...; k...), unit(s))
    #HACK: no function should be returned for queueing
    nothing
end
unit(::Call{V,T,U,N}) where {V,T,U,N} = U
#HACK: showing s.value could trigger StackOverflowError
show(io::IO, s::Call) = print(io, "<call>")

####

import DataStructures: OrderedDict

mutable struct Accumulate{V,R,T,U,RU,N} <: State{V}
    init::VarVal{V}
    time::TimeState{T}
    rates::OrderedDict{T,R}
    value::V
    cache::OrderedDict{T,V}
end

Accumulate(; init=0, unit=missing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    TU = timeunittype(time, _system)
    T = valuetype(_type_time, TU)
    #T = timetype(_type_time, time, _system)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    N = Symbol("$(name(_system))<$_name>")
    Accumulate{V,R,T,U,RU,N}(VarVal{V}(_system, init), TimeState{T}(_system, time), OrderedDict{T,R}(), default(V), OrderedDict{T,V}())
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
    store!(s, v)
    s.cache[t] = s.value
    r = unitfy(f(), rateunit(s))
    () -> (s.rates[t] = r) # s.cache = filter(p -> p.first == t, s.cache)
end
#TODO special handling of no return value for Accumulate/Capture?
#store!(s::Accumulate, ::Nothing) = store!(s, () -> 0)
unit(::Accumulate{V,R,T,U,RU,N}) where {V,R,T,U,RU,N} = U
rateunit(::Accumulate{V,R,T,U,RU,N}) where {V,R,T,U,RU,N} = RU
priority(s::Accumulate) = 2

####

mutable struct Capture{V,R,T,U,RU,N} <: State{V}
    time::TimeState{T}
    rate::R
    tick::T
    value::V
end

Capture(; unit=missing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    TU = timeunittype(time, _system)
    T = valuetype(_type_time, TU)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    t = TimeState{T}(_system, time)
    N = Symbol("$(name(_system))<$_name>")
    Capture{V,R,T,U,RU,N}(t, default(R), t.ticker.t, default(V))
end

check!(s::Capture) = checktime!(s)
store!(s::Capture, f::Function) = begin
    t = s.time.ticker.t
    v = s.rate * (t - s.tick)
    r = unitfy(f(), rateunit(s))
    () -> (store!(s, v); s.rate = r; s.tick = t)
end
#TODO special handling of no return value for Accumulate/Capture?
#store!(s::Capture, ::Nothing) = store!(s, () -> 0)
unit(s::Capture{V,R,T,U,RU,N}) where {V,R,T,U,RU,N} = U
rateunit(s::Capture{V,R,T,U,RU,N}) where {V,R,T,U,RU,N} = RU
priority(s::Capture) = 2

####

mutable struct Flag{Bool,P,T,N} <: State{Bool}
    value::Bool
    prob::VarVal{P}
    time::TimeState{T}
end

Flag(; prob=1, time="context.clock.tick", _name, _system, _type=Bool, _type_prob=Float64, _type_time=Float64, _...) = begin
    V = _type
    P = _type_prob
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Flag{V,P,T,N}(zero(V), VarVal{P}(_system, prob), TimeState{T}(_system, time))
end

check!(s::Flag) = checktime!(s) && checkprob!(s)
store!(s::Flag, f::Function) = (v = f(); () -> store!(s, v))
priority(s::Flag) = 1

####

mutable struct Produce{S<:System,T,N} <: State{S}
    system::System
    value::Vector{S}
    time::TimeState{T}
    name::Symbol # used in recurisve collecting in getvar!
end

struct Product{S<:System,K,V}
    type::Type{S}
    args::Vector{Pair{K,V}}
end

Produce(; time="context.clock.tick", _name, _system, _type::Type{S}=System, _type_time=Float64, _...) where {S<:System} = begin
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Produce{S,T,N}(_system, S[], TimeState{T}(_system, time), _name)
end

check!(s::Produce) = checktime!(s)
value(s::Produce{S}) where {S<:System} = s.value::Vector{S}
produce(s::Type{<:System}; args...) = Product(s, collect(args))
produce(s::Produce, p::Product) = append!(s.value, p.type(; context=s.system.context, p.args...))
produce(s::Produce, p::Vector{<:Product}) = produce.(Ref(s), p)
produce(s::Produce, ::Nothing) = nothing
store!(s::Produce, f::Function) = (p = f(); () -> produce(s, p))
store!(s::Produce, ::Nothing) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
priority(s::Produce) = -1

####

mutable struct Solve{V,T,U,N} <: State{V}
    value::V
    time::TimeState{T}
    lower::Union{VarVal{V},Nothing}
    upper::Union{VarVal{V},Nothing}
    context::System
    solving::Bool
end

Solve(; lower=nothing, upper=nothing, unit=missing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Solve{V,T,U,N}(default(V), TimeState{T}(_system, time), VarVal{V}(_system, lower), VarVal{V}(_system, upper), _system.context, false)
end

check!(s::Solve) = checktime!(s) && !s.solving
using Roots
store!(s::Solve, f::Function) = begin
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
unit(::Solve{V,T,U,N}) where {V,T,U,N} = U

export produce
