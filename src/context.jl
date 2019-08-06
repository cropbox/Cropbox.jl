@system Clock begin
    context ~ system(usearg)
    tick => gettime!(s.tick) ~ tock
    #unit
    start => 0 ~ track(init=0, time="tick") # parameter
    interval: i => 1 ~ track(init=1, time="tick") # parameter
    time(i) => i ~ accumulate(init=0, time="tick")
    #start_datetime ~ parameter
    #datetime
end bare

advance!(c::Clock) = advance!(c.tick.state)

const Config = Dict{Symbol,Any}
import DataStructures: DefaultDict
const Queue = DefaultDict{Priority,Vector{Function}}

@system Context begin
    clock => Clock(; context=self) ~ clock
    queue => Queue(Vector{Function}) ~ queue
    config => Config(config) ~ config(usearg)

    context => self ~ system
    parent => self ~ system
    children ~ [system]
end bare

#Config(::Nothing) = Config()
using TOML
Config(config::AbstractString) = begin
    conv(d) = d
    conv(d::Dict) = (Symbol(p.first) => conv(p.second) for p in d) |> collect
    TOML.parse(config) |> conv
end
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
preflush!(c::Context) = flush!(c, p -> p.first < default)
postflush!(c::Context) = flush!(c, p -> p.first >= default)

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
    advance!(c)
    s = SystemType(; context=c, parent=c)
    push!(c.children, s)
    advance!(c)
    s
end

export Clock, Context, Priority, configure!, option, update!, instance
