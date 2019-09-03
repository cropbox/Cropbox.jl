abstract type State{V} end

value(s::State{V}) where V = s.value::V

abstract type Step end
struct PreStep <: Step end
struct MainStep <: Step end
struct PostStep <: Step end

update!(s::State, f::AbstractVar, ::PreStep) = nothing
update!(s::State, f::AbstractVar, ::MainStep) = store!(s, f())
update!(s::State, f::AbstractVar, ::PostStep) = nothing

store!(s::State, v) = (s.value = unitfy(v, unit(s)); nothing)

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
    value(x.equation)
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
    v = value(x.equation)
    u = timeunittype(t, s)
    unitfy(v, u)
end
timevalue(t, _) = t

rateunittype(U::Nothing, TU::Unitful.Units) = TU^-1
rateunittype(U::Unitful.Units, TU::Unitful.Units) = U/TU
rateunittype(U::Unitful.Units, TU::Nothing) = U
rateunittype(U::Nothing, TU::Nothing) = nothing

abstract type Priority end
struct PrePriority <: Priority end
struct PostPriority <: Priority end

priority(::S) where {S<:State} = priority(S)
priority(::Type{<:State}) = PostPriority()

varfields(s::S) where {S<:State} = begin
    l = collect(zip(fieldnames(S), fieldtypes(S)))
    # contravariant for including i.e. Union{VarVal,Nothing}
    filter!(p -> p[2] <: Union{>:VarVal,TimeState}, l)
    map(p -> getfield(s, p[1]), l)
end

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
    #@show Symbol("$(name(_system))<$_name>")
    U = unittype(unit, _system)
    #@show U
    T = valuetype(_type, U)
    #@show _type
    #@show T
    t = isnothing(init) ? zero(T) : timevalue(init, _system)
    #@show zero(T)
    #@show timevalue(init, _system)
    #@show timeunittype(init, _system)
    #@show t
    dt = isnothing(step) ? oneunit(T) : timevalue(step, _system)
    #@show oneunit(T)
    #@show timevalue(step, _system)
    #@show timeunittype(step, _system)
    #@show dt
    T = promote_type(typeof(t), typeof(dt))
    #@show T
    N = Symbol("$(name(_system))<$_name>")
    #@show N
    Advance{T}(Timepiece{T}(t, dt))
end

value(s::Advance) = s.value.t
update!(s::Advance, f::AbstractVar, ::MainStep) = nothing
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)

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
        V = typeof(v)
    end
    N = Symbol("$(name(_system))<$_name>")
    Preserve{V}(v)
end

value(s::Preserve{V}) where V = s.value::Union{V,Missing}
#FIXME: make new interface similar to check!?
update!(s::Preserve, f::AbstractVar, ::MainStep) = ismissing(s.value) ? store!(s, f()) : nothing

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

update!(s::Drive, f::AbstractVar, ::MainStep) = store!(s, value(f()[s.key])) # value() for Var

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

value(s::Call{V}) where {V} = s.value::Union{V,Function}
update!(s::Call, f::AbstractVar, ::MainStep) = begin
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

update!(s::Accumulate, f::AbstractVar, ::MainStep) = begin
    t = value(s.time.tick)
    t0 = s.tick
    if ismissing(t0)
        #@show "missing"
        v = value(s.init)
    else
        #@show "$(s.value)"
        #@show "$(s.rate)"
        #@show "$t"
        #@show "$t0"
        v = s.value + s.rate * (t - t0)
    end
    #@show "acc store $v"
    store!(s, v)
end
update!(s::Accumulate, f::AbstractVar, ::PostStep) = begin
    #@show "accumulate post step!!!!!"
    t = value(s.time.tick)
    r = unitfy(f(), rateunit(s))
    () -> (#= @show "acc poststore $t, $r";=# s.tick = t; s.rate = r)
end
#TODO special handling of no return value for Accumulate/Capture?
#store!(s::Accumulate, ::Nothing) = update!(s, () -> 0)
rateunit(::Accumulate{V,T,R}) where {V,T,R} = unittype(R)

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

update!(s::Capture, f::AbstractVar, ::MainStep) = begin
    t = value(s.time.tick)
    t0 = s.tick
    if !ismissing(t0)
        v = s.rate * (t - t0)
        #@show "$(s.rate)"
        #@show "$t"
        #@show "$t0"
        #@show "$v"
        store!(s, v)
    end
end
update!(s::Capture, f::AbstractVar, ::PostStep) = begin
    t = value(s.time.tick)
    r = unitfy(f(), rateunit(s))
    #@show "capture post step!!!!! $t $r"
    () -> (s.tick = t; s.rate = r)
end
#TODO special handling of no return value for Accumulate/Capture?
#store!(s::Capture, ::Nothing) = update!(s, () -> 0)
rateunit(s::Capture{V,T,R}) where {V,T,R} = unittype(R)

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

update!(s::Flag, f::AbstractVar, ::MainStep) = nothing
update!(s::Flag, f::AbstractVar, ::PostStep) = (v = f(); () -> store!(s, v))

####

mutable struct Produce{S<:System,T} <: State{S}
    context::System
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
    Produce{S,T}(_system.context, S[], TimeState{T}(_system, time), _name)
end

value(s::Produce{S}) where {S<:System} = s.value::Vector{S}
produce(s::Type{<:System}; args...) = Product(s, args)
produce(s::Produce, p::Product, x::AbstractVar) = begin
    c = s.context
    k = p.type(; context=c, p.args...)
    append!(s.value, k)
    inform!(c.order, x, k)
end
produce(s::Produce, p::Vector{<:Product}, x::AbstractVar) = produce.(Ref(s), p, Ref(x))
produce(s::Produce, ::Nothing, x::AbstractVar) = nothing
update!(s::Produce, f::AbstractVar, ::MainStep) = nothing
update!(s::Produce, f::AbstractVar, ::PostStep) = (p = f(); () -> produce(s, p, f))
unit(s::Produce) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
priority(::Type{<:Produce}) = PrePriority()

####

mutable struct Solve{V,T} <: State{V}
    context::System
    value::V
    time::TimeState{T}
    lower::Union{VarVal{V},Nothing}
    upper::Union{VarVal{V},Nothing}
end

Solve(; lower=nothing, upper=nothing, unit=nothing, time="context.clock.tick", _name, _system, _type=Float64, _type_time=Float64, _...) = begin
    U = unittype(unit, _system)
    V = valuetype(_type, U)
    T = timetype(_type_time, time, _system)
    N = Symbol("$(name(_system))<$_name>")
    Solve{V,T}(_system.context, default(V), TimeState{T}(_system, time), VarVal{V}(_system, lower), VarVal{V}(_system, upper))
end

using Roots
update!(s::Solve, f::AbstractVar, ::PreStep) = nothing
update!(s::Solve, f::AbstractVar, ::MainStep) = begin
    #@show "begin solve $s"
    trigger(x) = (store!(s, x); recite!(s.context.order, f))
    cost(e) = x -> (trigger(x); e(x) |> ustrip)
    b = (value(s.lower), value(s.upper))
    if nothing in b
        try
            c = cost(x -> (x - f())^2)
            v = find_zero(c, value(s))
        catch e
            #@show "convergence failed: $e"
            v = value(s)
        end
    else
        c = cost(x -> (x - f()))
        v = find_zero(c, b, Roots.AlefeldPotraShi())
    end
    #HACK: trigger update with final value
    trigger(v)
    recitend!(s.context.order, f)
end

export produce
