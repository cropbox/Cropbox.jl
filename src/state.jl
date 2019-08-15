abstract type State end

check!(s::State) = true
value(s::State) = s.value
store!(s::State, f::Function) = store!(s, f())
store!(s::State, v) = (s.value = unitfy(v, unit(s)))
store!(s::State, ::Nothing) = nothing

checktime!(s::State) = (update!(s.tick, value!(s.time)) > 0)
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
# function show(io::IO, s::State)
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

mutable struct Tock{T,U} <: State
    value::Tick{T}
end

Tock(; unit=NoUnits, _type=Int64, _...) = (V = valuetype(_type, unit); Tock{V,unit}(Tick(V(0))))

check!(s::Tock) = false
advance!(s::Tock) = advance!(s.value)
unit(::Tock{T,U}) where {T,U} = U

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
    time::VarVal
    tick::Tick{T}
end

Track(; unit=NoUnits, time="context.clock.time", tick::Tick{T}=Tick(0.), _system, _type=Float64, _...) where T = begin
    V = valuetype(_type, unit)
    Track{V,T,unit}(VarVal.(_system, [V(0), time, tick])...)
end

check!(s::Track) = begin
    checktime!(s) && (return true)
    #isnothing(s.value) && (s.value = s.initial_value; return true)
    #TODO: regime handling
    return false
end
unit(::Track{V,T,U}) where {V,T,U}  = U

####

import DataStructures: OrderedDict

mutable struct Accumulate{V,T,U} <: State
    init::VarVal{V}
    time::VarVal
    tick::Tick{T}
    rates::OrderedDict{T,V}
    value::VarVal{V}
end

Accumulate(; init=0, unit=NoUnits, time="context.clock.time", tick::Tick{T}=Tick(0.), _system, _type=Float64, _...) where T = begin
    V = valuetype(_type, unit)
    v = VarVal{V}(_system, init)
    Accumulate{V,T,unit}(v, VarVal.(_system, [time, tick])..., OrderedDict{T,_type}(), v)
end

check!(s::Accumulate) = checktime!(s)
store!(s::Accumulate, f::Function) = begin
    t = s.tick.t
    T0 = collect(keys(s.rates))
    T1 = [T0; t][2:length(T0)+1]
    v = value!(s.init) + sum((T1 - T0) .* values(s.rates))
    s.value = unitfy(v, unit(s))
    () -> (s.rates[t] = f())
end
unit(::Accumulate{V,T,U}) where {V,T,U} = U
priority(s::Accumulate) = 2

####

# Difference can be actually Track
# mutable struct Difference{V,T} <: State end

####

mutable struct Flag{T} <: State
    value::Bool
    prob::VarVal
    time::VarVal
    tick::Tick{T}
end

Flag(; prob=1, time="context.clock.time", tick=Tick(0.), _system, _type=Bool, _...) = Flag(VarVal.(_system, [zero(_type), prob, time, tick])...)

check!(s::Flag) = checktime!(s) && checkprob!(s)
priority(s::Flag) = 1

####

mutable struct Produce{S<:System,T} <: State
    system::System
    value::Vector{S}
    time::VarVal
    tick::Tick{T}
end

struct Product{S<:System,K,V}
    type::Type{S}
    args::Vector{Pair{K,V}}
end

Produce(; time="context.clock.time", tick::Tick{T}=Tick(0.), _system, _type::Type{S}=System, _...) where {S<:System,T} = Produce{S,T}(VarVal.(_system, [_system, S[], time, tick])...)

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

export State, Pass, Tock, Preserve, Track, Accumulate, Flag, Produce
export check!, value, store!, priority, advance!, produce
