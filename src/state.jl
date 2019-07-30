abstract type State end

check!(s::State, t) = true
value(s::State) = s.value
store!(s::State, v) = (!isnothing(v) && (s.value = v))
store!(s::State, f::Function) = store!(s, f())
poststore!(s::State, f::Function) = () -> return
poststore!(s::State, v) = poststore!(s, () -> v)

# import Base: show
# function show(io::IO, s::State)
#     v = value(s)
#     print(io, "<$(s.name)> = $(isnothing(v) ? "<uninitialized>" : v)")
# end

####

mutable struct Tock <: State
    value::Tick
end

Tock(;_...) = Tock(Tick(0))

check!(s::Tock, t) = false
advance!(s::Tock) = (s.value += 1)

####

mutable struct Track{V} <: State
    value::V
    tick::Tick
end

Track(;init=0., _...) = Track(init, Tick(0))

function check!(s::Track, t)
    (update!(s.tick, t) > 0) && (return true)
    #isnothing(s.value) && (s.value = s.initial_value; return true)
    #TODO: regime handling
    return false
end

####

using DataStructures

mutable struct Accumulate{V,T} <: State
    initial_value::V
    tick::Tick{T}
    rates::OrderedDict{T,V}
    value::V
end

Accumulate(v::V, t::Tick{T}) where {V,T} = Accumulate(v, t, OrderedDict{T,V}(), v)
Accumulate(;init=0., _...) = Accumulate(init, Tick(0))

check!(s::Accumulate, t) = (update!(s.tick, t) > 0) && (return true)

function store!(s::Accumulate, v)
    t = s.tick
    T0 = collect(keys(s.rates))
    T1 = [T0; t][2:length(T0)+1]
    s.value = s.initial_value + sum((T1 - T0) .* values(s.rates))
end

function poststore!(s::Accumulate, f::Function)
    t = s.tick
    return function ()
        s.rates[t] = f()
    end
end

export State, Tock, Track, Accumulate
export check!, value, store!, poststore!, advance!
