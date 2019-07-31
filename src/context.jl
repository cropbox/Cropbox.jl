@system Clock begin
    tick => gettime!(s.tick) ~ tock(time="")
    #unit
    start => 0 ~ track(init=0, time="tick") # parameter
    interval: i => 1 ~ track(init=1, time="tick") # parameter
    time(i) => i ~ accumulate(init=0, time="tick")
    #start_datetime ~ parameter
    #datetime
end bare

advance!(c::Clock) = advance!(c.tick.state)

@enum Priority default=0 flag=1 accumulate=2 produce=-1

const Config = Dict{Symbol,Any}
const Queue = Dict{Priority,Vector{Function}}

@system Context begin
    clock ~ clock
    queue ~ queue
    config => Config(config) ~ config(usearg)

    context ~ system(self)
    parent ~ system(self)
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
option(c::Config, key::Symbol, keys...) = option(get(c, k, nothing), keys...)
option(c::Config, key::Vector{Symbol}, keys...) = begin
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
