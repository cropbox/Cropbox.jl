abstract type State{V} end

check!(s::State) = true
value(s::State{V}) where V = s.value::V

abstract type Step end
struct PreStep <: Step end
struct MainStep <: Step end
struct PostStep <: Step end

#TODO: rename store!(s, f, _) to update!(s, f, _)?
#store!(s::State, f::AbstractVar) = store!(s, f, MainStep())
store!(s::State, f::AbstractVar, ::PreStep) = nothing
store!(s::State, f::AbstractVar, ::MainStep) = store!(s, f())
store!(s::State, f::AbstractVar, ::PostStep) = nothing

store!(s::State, v) = (s.value = unitfy(v, unit(s)); nothing)

checktime!(s::State) = check!(s.time)
checkprob!(s::State) = (p = value(s.prob); (p >= 1 || rand() <= p))

import Base: getindex, length, iterate
getindex(s::State, i) = s
length(s::State) = 1
iterate(s::State) = (s, nothing)
iterate(s::State, i) = nothing

default(V::Type{<:Number}) = V(0)
default(V::Type) = V()

import Unitful: unit
unit(::State{V}) where V = unittype(V)
unittype(V) = ((V <: Quantity) ? unit(V) : nothing)

unittype(::Nothing, _) = nothing
unittype(U::Unitful.Units, _) = U
unittype(unit::String, s::System) = begin
    x = getvar(s, unit)
    #FIXME: ensure only access static values on init
    @assert typeof(x.equation) <: StaticEquation
    value(x)
end

valuetype(::State{V}) where V = V
valuetype(T, ::Nothing) = T
valuetype(T, U::Unitful.Units) = Quantity{T, dimension(U), typeof(U)}
valuetype(::Type{Array{T,N}}, U::Unitful.Units) where {T,N} = Array{valuetype(T, U), N}

#HACK: state var referred by `time` tag must have been already declared
timeunittype(time::String, s::System) = unit(state(getvar(s, time)))
timetype(T, time::String, s::System) = valuetype(T, timeunittype(time, s))
timevalue(t::String, s::System) = begin
    x = getvar(s, t)
    #FIXME: ensure only access static values on init
    @assert typeof(x.equation) <: StaticEquation
    value(x)
end
timevalue(t, _) = t

rateunittype(U::Nothing, TU::Unitful.Units) = TU^-1
rateunittype(U::Unitful.Units, TU::Unitful.Units) = U/TU
rateunittype(U::Unitful.Units, TU::Nothing) = U
rateunittype(U::Nothing, TU::Nothing) = nothing

priority(::S) where {S<:State} = priority(S)
priority(::Type{<:State}) = 0 # low is low
flushorder(::S) where {S<:State} = flushorder(S)
flushorder(::Type{<:State}) = 1 # post = 1, pre = -1

varfields(s::S) where {S<:State} = begin
    l = collect(zip(fieldnames(S), fieldtypes(S)))
    filter!(p -> p[2] <: Union{VarVal,TimeState}, l)
    map(p -> getfield(s, p[1]), l)
end

import Base: show
show(io::IO, s::State) = print(io, "$(repr(value(s)))")

####

mutable struct Pass{V} <: State{V}
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
    Pass{V}(v)
end

####

mutable struct Advance{T} <: State{T}
    value::Timepiece{T}
end

Advance(; init=nothing, step=nothing, unit=nothing, _name, _system, _type=Int64, _...) = begin
    U = unittype(unit, _system)
    T = valuetype(_type, U)
    t = isnothing(init) ? zero(T) : timevalue(init, _system)
    dt = isnothing(step) ? oneunit(T) : timevalue(step, _system)
    T = promote_type(typeof(t), typeof(dt))
    N = Symbol("$(name(_system))<$_name>")
    Advance{T}(Timepiece{T}(t, dt))
end

check!(s::Advance) = false
value(s::Advance) = s.value.t
store!(s::Advance, f::AbstractVar, ::MainStep) = nothing
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)
priority(::Type{<:Advance}) = 10

####

mutable struct Preserve{V} <: State{V}
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
    Preserve{V}(v)
end

check!(s::Preserve) = ismissing(s.value)
value(s::Preserve{V}) where V = s.value::Union{V,Missing}
#FIXME: make new interface similar to check!?
store!(s::Preserve, f::AbstractVar, ::MainStep) = ismissing(s.value) ? store!(s, f()) : nothing
priority(::Type{<:Preserve}) = 1

####

mutable struct Track{V,T} <: State{V}
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
    Track{V,T}(v, TimeState{T}(_system, time))
end

check!(s::Track) = checktime!(s)

####

mutable struct Drive{V,T} <: State{V}
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
    Drive{V,T}(k, default(V), TimeState{T}(_system, time))
end

check!(s::Drive) = checktime!(s)
store!(s::Drive, f::AbstractVar, ::MainStep) = store!(s, value(f()[s.key])) # value() for Var

####

mutable struct Call{V,T} <: State{V}
    value::Union{Function,Missing}
    time::TimeState{T}
end

Call(; unit=nothing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Call{V,T}(missing, TimeState{T}(_system, time))
end

check!(s::Call) = checktime!(s)
value(s::Call{V}) where {V} = s.value::Union{V,Function}
store!(s::Call, f::AbstractVar, ::MainStep) = begin
    s.value = (a...; k...) -> unitfy(f()(a...; k...), unit(s))
    #HACK: no function should be returned for queueing
    nothing
end
#HACK: showing s.value could trigger StackOverflowError
show(io::IO, s::Call) = print(io, "<call>")

####

mutable struct Accumulate{V,T,R} <: State{V}
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
    Accumulate{V,T,R}(VarVal{V}(_system, init), TimeState{T}(_system, time), missing, default(R), default(V))
end

check!(s::Accumulate) = checktime!(s)
store!(s::Accumulate, f::AbstractVar, ::MainStep) = begin
    t = value(s.time.tick)
    t0 = s.tick
    if ismissing(t0)
        @show "missing"
        v = value(s.init)
    else
        @show "$(s.value)"
        @show "$(s.rate)"
        @show "$t"
        @show "$t0"
        v = s.value + s.rate * (t - t0)
    end
    @show "acc store $v"
    store!(s, v)
end
store!(s::Accumulate, f::AbstractVar, ::PostStep) = begin
    @show "accumulate post step!!!!!"
    t = value(s.time.tick)
    r = unitfy(f(), rateunit(s))
    () -> (#= @show "acc poststore $t, $r";=# s.tick = t; s.rate = r)
end
#TODO special handling of no return value for Accumulate/Capture?
#store!(s::Accumulate, ::Nothing) = store!(s, () -> 0)
rateunit(::Accumulate{V,T,R}) where {V,T,R} = unittype(R)
priority(::Type{<:Accumulate}) = 8

####

mutable struct Capture{V,T,R} <: State{V}
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
    Capture{V,T,R}(TimeState{T}(_system, time), missing, default(R), default(V))
end

check!(s::Capture) = checktime!(s)
store!(s::Capture, f::AbstractVar, ::MainStep) = begin
    t = value(s.time.tick)
    t0 = s.tick
    if !ismissing(t0)
        v = s.rate * (t - t0)
        store!(s, v)
    end
end
store!(s::Capture, f::AbstractVar, ::PostStep) = begin
    t = value(s.time.tick)
    r = unitfy(f(), rateunit(s))
    () -> (s.tick = t; s.rate = r)
end
#TODO special handling of no return value for Accumulate/Capture?
#store!(s::Capture, ::Nothing) = store!(s, () -> 0)
rateunit(s::Capture{V,T,R}) where {V,T,R} = unittype(R)
priority(::Type{<:Capture}) = 6

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
store!(s::Flag, f::AbstractVar, ::MainStep) = nothing
store!(s::Flag, f::AbstractVar, ::PostStep) = (v = f(); () -> store!(s, v))
priority(::Type{<:Flag}) = 4

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
store!(s::Produce, f::AbstractVar, ::MainStep) = nothing
store!(s::Produce, ::Nothing) = nothing
store!(s::Produce, f::AbstractVar, ::PostStep) = (p = f(); () -> produce(s, p))
unit(s::Produce) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
priority(::Type{<:Produce}) = 3
flushorder(::Type{<:Produce}) = -1

####

mutable struct Solve{V,T} <: State{V}
    value::V
    time::TimeState{T}
    lower::Union{VarVal{V},Nothing}
    upper::Union{VarVal{V},Nothing}
    context::System
    solving::Bool
    error::Float64
    tol::VarVal{V}
end

Solve(; lower=nothing, upper=nothing, tol=1e-3, unit=nothing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Solve{V,T}(default(V), TimeState{T}(_system, time), VarVal{V}(_system, lower), VarVal{V}(_system, upper), _system.context, false, Inf, VarVal{V}(_system, tol))
end

check!(s::Solve) = begin
    t = value(s.time.tick)
    if value(s.time.tick) < t
        #@show "reset error = Inf since $(value(s.time.tick)) < $t"
        #@show s.solving
        s.error = Inf
    end
    checktime!(s) && !s.solving
end
using Roots
store!(s::Solve, f::AbstractVar, ::PreStep) = nothing
store!(s::Solve, f::AbstractVar, ::MainStep) = begin
    #@show "begin solve $s"
    s.solving = true
    y = f() |> ustrip
    if s.error == y
        #@show "skip solve s.error = $(s.error) == y = $y"
        check!(s)
        s.solving = false
        return
    elseif s.error < y
        #@show "error $(s.error) < y = $(y)"
    end
    cost(x) = begin
        store!(s, x)
        reupdate!(s.context.order)
        y = f() |> ustrip
        #@show "cost x = $x ~ error = $y"
        if y < s.error
            #@show "update error: $(s.error) => $y"
            s.error = y
        end
        y
    end
    b = (value(s.lower), value(s.upper))
    if nothing in b
        try
            v = find_zero(cost, value(s); xatol=value(s.tol))
        catch e
            #@show "convergence failed: $e"
            v = value(s)
            s.error = f() |> ustrip
            s.solving = false
        end
    else
        v = find_zero(cost, b)
    end
    #FIXME: ensure all state vars are updated once and only once (i.e. no duplice produce)
    #HACK: trigger update with final value
    #store!(s, v); #recite!(s.context); #update!(s.context)
    s.solving = false
    #@show "end solve $s"
    check!(s)
    #@show "$(s.context.clock.tick)"
    #@show "$(s.context.clock.tock)"
    #@show "$(s.time)"
    store!(s, v)
end
priority(::Type{<:Solve}) = 9

export produce
