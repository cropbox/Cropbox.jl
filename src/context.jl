mutable struct Clock <: System
    tick::Statevar
    #unit::Statevar
    start::Statevar
    interval::Statevar
    time::Statevar
    #start_datetime::Statevar
    #datetime::Statevar

    function Clock()
        s = new()
        # s.tick = Statevar(s, () -> gettime!(s.tick), Tock())
        s.tick = Statevar(s, () -> gettime!(s.tick), Tock; name=:tick)
        #s.unit
        # s.start = Statevar(s, () -> 0, Track(;init=0), s.tick) # Parameter
        # s.interval = Statevar(s, () -> 1, Track(;init=1), s.tick) # Parameter
        # s.time = Statevar(s, (interval) -> interval, Accumulate(init=0), s.tick)
        s.start = Statevar(s, () -> 0, Track; name=:start, init=0, time=s.tick) # Parameter
        s.interval = Statevar(s, () -> 1, Track; name=:interval, init=1, time=s.tick) # Parameter
        s.time = Statevar(s, (interval) -> interval, Accumulate; name=:time, init=0, time=s.tick)
        #s.start_datetime # Parameter
        #s.datetime
        s
    end
end

# @system Clock begin
#     tick => gettime!(s.tick) ~ tock
#     start => 0 ~ track(init=0, time="tick")
#     interval: i => 1 ~ track(init=1, time="tick")
#     time(i) => i ~ accumulate(init=0, time="tick")
# end bare

advance!(c::Clock) = advance!(c.tick.state)

@enum Priority default=0 flag=1 accumulate=2 produce=-1

const Config = Dict{Symbol,Any}
const Queue = Dict{Priority,Array{Function}}

QueueType =
mutable struct Context <: System
    clock::System
    queue::Queue
    config::Config

    context::System
    parent::System
    children::Array{System}

    function Context(; config)
        c = new()
        c.clock = Clock()
        c.queue = Queue()
        c.config = Config(config)

        c.context = c
        c.parent = c
        c.children = System[]
        c
    end
end

# @system Context begin
#     clock ~ clock
#     queue ~ queue
#     config => Config(config) ~ config(usearg)
# end

#Config(::Nothing) = Config()
using TOML
Config(config::AbstractString) = begin
    conv(d) = d
    conv(d::Dict) = (Symbol(p.first) => conv(p.second) for p in d) |> collect
    TOML.parse(config) |> conv
end
option(c) = c
option(c, keys...) = nothing
option(c::Config, key::Symbol, keys...) = option(get(c, k, nothing), keys...)
option(c::Config, key::Array{Symbol}, keys...) = begin
    for k in key
        v = option(c, k, keys...)
        !isnothing(v) && return v
    end
    nothing
end
#option(c::Config, key::Statevar, keys...) = option(c, expand(key.alias), keys...) #TODO
option(c::Context, keys...) = option(c.config, keys...)

queue!(c::Context, f::Function, p::Priority=default) = push!(c.queue[p], f)
flush!(c::Context, cond) = foreach(f -> f(), filter(cond, c.queue) |> values |> Iterators.flatten)
preflush!(c::Context) = flush!(c, p -> p.first >= default)
postflush!(c::Context) = flush!(c, p -> p.first < default)

function update!(c::Context)
    # process pending operations from last timestep (i.e. produce)
    preflush!(c)

    # update state variables recursively
    update!(c.clock)
    foreach(update!, collect(c))

    # process pending operations from current timestep (i.e. flag, accumulate)
    postflush!(c)

    #TODO: process aggregate (i.e. transport) operations?
end

advance!(c::Context) = (advance!(c.clock); update!(c))

function instance(SystemType::Type{S}, config=Config()) where {S<:System}
    c = Context(; config=config)
    s = SystemType(; context=c, parent=c)
    push!(c.children, s)
    update!(c)
    s
end

export Clock, Context, Priority, configure!, option, update!, instance
