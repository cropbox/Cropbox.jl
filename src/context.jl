@system Clock begin
    self => self ~ ::System
    context ~ ::System(usearg)
    tick => gettime!(s.tick) ~ tock
    #unit
    start => 0 ~ track(time="tick") # parameter
    interval: i => 1 ~ track(time="tick") # parameter
    time(i) => i ~ accumulate(init=0, time="tick")
    #start_datetime ~ parameter
    #datetime
end bare

advance!(c::Clock) = advance!(c.tick)

const Config = Dict #TODO: proper struct?
import DataStructures: DefaultDict
const Queue = DefaultDict{Priority,Vector{Function}}

@system Context begin
    self => self ~ ::System
    context => self ~ ::System
    systems ~ ::[System]

    config => Config() ~ ::Config(override)
    queue => Queue(Vector{Function}) ~ ::Queue
    clock => Clock(; context=self) ~ ::Clock
end bare

config(c::Dict) = Dict(Symbol(p.first) => config(p.second) for p in c)
config(c) = c
using TOML
Config(c::AbstractString) = config(TOML.parse(c))
Config(c::Dict) = config(c)

option(c) = c
option(c, keys...) = nothing
option(c::Config, key::Symbol, keys...) = option(get(c, key, nothing), keys...)
option(c::Config, key::Vector{Symbol}, keys...) = begin
    for k in key
        v = option(c, k, keys...)
        !isnothing(v) && return v
    end
    nothing
end
option(c::Config, key::System, keys...) = option(c, Symbol(typeof(key)), keys...)
option(c::Config, key::Var, keys...) = option(c, names(key), keys...)
option(c::Context, keys...) = option(c.config, keys...)

queue!(c::Context, f::Function, p::Priority) = push!(c.queue[p], f)
queue!(c::Context, f, p::Priority) = nothing
flush!(c::Context, cond) = begin
    q = filter(cond, c.queue)
    filter!(!cond, c.queue)
    foreach(f -> f(), q |> values |> Iterators.flatten)
end
preflush!(c::Context) = flush!(c, p -> p.first < 0)
postflush!(c::Context) = flush!(c, p -> p.first >= 0)

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
advance!(s::System) = advance!(s.context)

function instance(SystemType::Type{S}, config=Config()) where {S<:System}
    c = Context(; config=config)
    advance!(c)
    s = SystemType(; context=c)
    push!(c.systems, s)
    advance!(c)
    s
end

export Clock, Context, Priority, Config, option, update!, instance
