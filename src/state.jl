abstract type State end

check!(s::State) = true
value(s::State) = s.value
store!(s::State, f::Function) = store!(s, f())
store!(s::State, v) = (s.value = v)
store!(s::State, ::Nothing) = nothing

import Base: getindex, length, iterate
getindex(s::State, i) = s
length(s::State) = 1
iterate(s::State) = (s, nothing)
iterate(s::State, i) = nothing

const Priority = Int
priority(s::State) = 0

# import Base: show
# function show(io::IO, s::State)
#     v = value(s)
#     print(io, "<$(s.name)> = $(isnothing(v) ? "<uninitialized>" : v)")
# end

####

mutable struct Pass{V} <: State
    value::V
end

Pass(; init=0., _...) = Pass(init)

####

const Tock = Pass{Tick}
Tock(; init=0, _...) = Tock(Tick(init))

check!(s::Tock) = false
advance!(s::Tock) = (s.value += 1)

####

mutable struct Track{V,T} <: State
    value::V
    time::VarVal
    tick::Tick{T}
end

Track(; init=0., time="context.clock.time", tick=Tick(0.), system, _...) = Track(VarVal.(system, [init, time, tick])...)

check!(s::Track) = begin
    (update!(s.tick, value!(s.time)) > 0) && (return true)
    #isnothing(s.value) && (s.value = s.initial_value; return true)
    #TODO: regime handling
    return false
end

####

import DataStructures: OrderedDict

mutable struct Accumulate{V,T} <: State
    initial_value::V
    time::VarVal
    tick::Tick{T}
    rates::OrderedDict{T,V}
    value::V
end

Accumulate(v::V, tm, t::Tick{T}) where {V,T} = Accumulate(v, tm, t, OrderedDict{T,V}(), v)
Accumulate(; init=0., time="context.clock.time", tick=Tick(0.), system, _...) = Accumulate(VarVal.(system, [init, time, tick])...)

check!(s::Accumulate) = (update!(s.tick, value!(s.time)) > 0) && (return true)
store!(s::Accumulate, f::Function) = begin
    t = s.tick
    T0 = collect(keys(s.rates))
    T1 = [T0; t][2:length(T0)+1]
    s.value = s.initial_value + sum((T1 - T0) .* values(s.rates))
    () -> (s.rates[t] = f())
end
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

Flag(; init=false, prob=1, time="context.clock.time", tick=Tick(0.), system, _...) = Flag(VarVal.(system, [init, prob, time, tick])...)

check!(s::Flag) = begin
    t = value!(s.time)
    p = value!(s.prob)
    (update!(s.tick, t) > 0) && (p >= 1 || rand() <= p) && (return true)
end
priority(s::Flag) = 1

####

mutable struct Produce{S<:System,T} <: State
    system::System
    value::Vector{S}
    time::VarVal
    tick::Tick{T}
end
const ProductArg = Pair{Symbol,Any}
const Product = Vector{<:Pair{Symbol,<:Any}}
const Products = Vector{<:Product}

Produce(; type::Type{S}, time="context.clock.time", tick::Tick{T}=Tick(0.), system, _...) where {S<:System,T} = Produce{S,T}(VarVal.(system, [system, S[], time, tick])...)

check!(s::Produce) = (update!(s.tick, value!(s.time)) > 0) && (return true)
produce(s::Produce{S}, p::Product) where {S<:System} = append!(s.value, S(; context=s.system.context, p...))
produce(s::Produce, p::Products) = produce.(s, p)
produce(s::Produce, ::Nothing) = produce(s, ProductArg[])
store!(s::Produce, f::Function) = () -> produce(s, f())
getindex(s::Produce, i) = getindex(s.value, i)
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
priority(s::Produce) = -1

export State, Pass, Tock, Track, Accumulate, Flag, Produce
export check!, value, store!, priority, advance!
