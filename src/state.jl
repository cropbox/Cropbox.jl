abstract type State end

check!(s::State) = true
value(s::State) = s.value
store!(s::State, f::Function) = (v = f(); !isnothing(v) && (s.value = v))
store!(s::State, v) = store!(s, () -> v)
poststore!(s::State, f::Function) = nothing
poststore!(s::State, v) = poststore!(s, () -> v)

@enum Priority default=0 flag=1 accumulate=2 produce=-1
priority(s::State) = default

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
    time::VarVal{T}
    tick::Tick{T}
end

Track(; init=0., time="context.clock.time", tick=Tick(0.), system, _...) = Track(VarVal.(system, [init, time, tick])...)

check!(s::Track) = begin
    t = getvar!(s.time)
    (update!(s.tick, t) > 0) && (return true)
    #isnothing(s.value) && (s.value = s.initial_value; return true)
    #TODO: regime handling
    return false
end

####

import DataStructures: OrderedDict

mutable struct Accumulate{V,T} <: State
    initial_value::V
    time::VarVal{T}
    tick::Tick{T}
    rates::OrderedDict{T,V}
    value::V
end

Accumulate(v::V, tm, t::Tick{T}) where {V,T} = Accumulate(v, tm, t, OrderedDict{T,V}(), v)
Accumulate(; init=0., time="context.clock.time", tick=Tick(0.), system, _...) = Accumulate(VarVal.(system, [init, time, tick])...)

check!(s::Accumulate) = (update!(s.tick, getvar!(s.time)) > 0) && (return true)
store!(s::Accumulate, f::Function) = begin
    t = s.tick
    T0 = collect(keys(s.rates))
    T1 = [T0; t][2:length(T0)+1]
    s.value = s.initial_value + sum((T1 - T0) .* values(s.rates))
end
poststore!(s::Accumulate, f::Function) = begin
    t = s.tick
    return function ()
        s.rates[t] = f()
    end
end
priority(s::Accumulate) = accumulate

####

# Difference can be actually Track
# mutable struct Difference{V,T} <: State end

####

mutable struct Flag{T} <: State
    value::Bool
    prob::VarVal
    time::VarVal{T}
    tick::Tick{T}
end

Flag(; init=false, prob=1, time="context.clock.time", tick=Tick(0.), system, _...) = Flag(VarVal.(system, [init, prob, time, tick])...)

check!(s::Flag) = begin
    t = getvar!(s.time)
    p = getvar!(s.prob)
    (update!(s.tick, t) > 0) && (p >= 1 || rand() <= p) && (return true)
end
store!(s::Flag, f::Function) = (s.value = f())
priority(s::Flag) = flag

####

mutable struct Produce <: State

end

# priority(s::Produce) = produce

export State, Pass, Tock, Track, Accumulate, Flag, Priority
export check!, value, store!, poststore!, priority, advance!
