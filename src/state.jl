abstract type State end

check!(s::State, _...) = true
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

check!(s::Tock, t) = false
advance!(s::Tock) = (s.value += 1)

####

mutable struct Track{V} <: State
    value::V
    tick::Tick
end

Track(;init=0., _...) = Track(init, Tick(0.))

check!(s::Track, t) = begin
    (update!(s.tick, t) > 0) && (return true)
    #isnothing(s.value) && (s.value = s.initial_value; return true)
    #TODO: regime handling
    return false
end

####

import DataStructures: OrderedDict

mutable struct Accumulate{V,T} <: State
    initial_value::V
    tick::Tick{T}
    rates::OrderedDict{T,V}
    value::V
end

Accumulate(v::V, t::Tick{T}) where {V,T} = Accumulate(v, t, OrderedDict{T,V}(), v)
Accumulate(;init=0., _...) = Accumulate(init, Tick(0.))

check!(s::Accumulate, t) = (update!(s.tick, t) > 0) && (return true)
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

mutable struct Flag <: State
    value::Bool
    prob
    tick::Tick
end

Flag(; init=false, prob=1, _...) = Flag(init, prob, Tick(0.))

check!(s::Flag, t, p) = (update!(s.tick, t) > 0) && (p >= 1 || rand() <= p) && (return true)
store!(s::Flag, f::Function) = (s.value = f())
priority(s::Flag) = flag

####

mutable struct Produce <: State

end

# priority(s::Produce) = produce

export State, Pass, Tock, Track, Accumulate, Flag, Priority
export check!, value, store!, poststore!, priority, advance!
