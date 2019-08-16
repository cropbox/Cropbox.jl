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

import Unitful: unit
unit(s::State) = NoUnits
valuetype(T, U::Unitful.DimensionlessUnits) = T
valuetype(T, U::Unitful.Units) = Quantity{T, dimension(U), typeof(U)}

const Priority = Int
priority(s::State) = 0

# import Base: show
# show(io::IO, s::State) = begin
#     v = value(s)
#     print(io, "<$(s.name)> = $(isnothing(v) ? "<uninitialized>" : v)")
# end

####

mutable struct Pass{V,U} <: State
    value::V
end

Pass(; unit=NoUnits, _type=Float64, _...) = (V = valuetype(_type, unit); Pass{V,unit}(V(0)))

unit(::Pass{V,U}) where {V,U} = U

####

mutable struct Advance{T,U} <: State
    value::Timepiece{T}
end

Advance(; unit=NoUnits, _type=Int64, _...) = (T = valuetype(_type, unit); Advance{T,unit}(Timepiece(T(0))))

check!(s::Advance) = false
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)
unit(::Advance{T,U}) where {T,U} = U

####

mutable struct Preserve{V,U} <: State
    value::Union{V,Missing}
end

Preserve(; unit=NoUnits, _type=Float64, _...) = (V = valuetype(_type, unit); Preserve{V,unit}(missing))

check!(s::Preserve) = ismissing(s.value)
unit(::Preserve{V,U}) where {V,U} = U

####

mutable struct Track{V,T,U} <: State
    value::V
    time::TimeState{T}
end

Track(; unit=NoUnits, time="context.clock.time", _system, _type=Float64, _type_time=Float64, _...) = begin
    V = valuetype(_type, unit)
    T = _type_time
    Track{V,T,unit}(V(0), TimeState{T}(_system, time))
end

check!(s::Track) = begin
    checktime!(s) && (return true)
    #isnothing(s.value) && (s.value = s.initial_value; return true)
    #TODO: regime handling
    return false
end
unit(::Track{V,T,U}) where {V,T,U} = U

####

import DataStructures: OrderedDict

mutable struct Accumulate{V,T,U} <: State
    init::VarVal{V}
    time::TimeState{T}
    rates::OrderedDict{T,V}
    value::V
    cache::OrderedDict{T,V}
end

Accumulate(; init=0, unit=NoUnits, time="context.clock.time", _system, _type=Float64, _type_time=Float64, _...) = begin
    V = valuetype(_type, unit)
    T = _type_time
    Accumulate{V,T,unit}(VarVal{V}(_system, init), TimeState{T}(_system, time), OrderedDict{T,_type}(), V(0), OrderedDict{T,_type}())
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
    () -> (s.rates[t] = f()) # s.cache = filter(p -> p.first == t, s.cache)
end
unit(::Accumulate{V,T,U}) where {V,T,U} = U
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

Flag(; prob=1, time="context.clock.time", _system, _type=Bool, _type_prob=Float64, _type_time=Float64, _...) = begin
    V = _type
    P = _type_prob
    T = _type_time
    Flag(zero(V), VarVal{P}(_system, prob), TimeState{T}(_system, time))
end

check!(s::Flag) = checktime!(s) && checkprob!(s)
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

Produce(; time="context.clock.time", _system, _type::Type{S}=System, _type_time=Float64, _...) where {S<:System} = begin
    T = _type_time
    Produce{S,T}(_system, S[], TimeState{T}(_system, time))
end

check!(s::Produce) = checktime!(s)
produce(s::Type{S}; args...) where {S<:System} = Product(s, collect(args))
produce(s::Produce, p::Product) = append!(s.value, p.type(; context=s.system.context, p.args...))
produce(s::Produce, p::Vector{Product}) = produce.(s, p)
produce(s::Produce, ::Nothing) = nothing
store!(s::Produce, f::Function) = () -> produce(s, f())
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

Solve(; lower=nothing, upper=nothing, unit=NoUnits, time="context.clock.time", _system, _type=Float64, _type_time=Float64, _...) = begin
    V = valuetype(_type, unit)
    T = _type_time
    Solve{V,T,unit}(V(0), TimeState{T}(_system, time), VarVal{V}(_system, lower), VarVal{V}(_system, upper), _system.context.clock, false)
end

check!(s::Solve) = checktime!(s) && !s.solving
using Roots
store!(s::Solve, f::Function) = begin
    s.solving = true
    #println("s.clock.time = $(s.clock.time)")
    cost(x) = begin
        #println("cost begin x = $x, t = $(s.clock.tock)");
        store!(s, x);
        recite!(s.clock);
        y = f();
        #println("cost end y = $y");
        y
    end
    b = (value!(s.lower), value!(s.upper))
    if nothing in b
        v = find_zero(cost, value(s))
    else
        v = find_zero(cost, b, Roots.AlefeldPotraShi())
    end
    #FIXME: no longer needed with regime?
    #HACK: trigger update with final value
    cost(v)
    s.solving = false
    store!(s, v)
end
unit(::Solve{V,T,U}) where {V,T,U} = U

export produce
