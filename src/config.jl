const Config = Dict{Any,Any}

configure(c::Dict) = Config(Symbol(p.first) => configure(p.second) for p in c)
configure(c::Tuple) = configure(Config(c))
configure(c::Pair...) = configure(Config(c...))
configure(c) = c

using TOML
loadconfig(c::AbstractString) = configure(TOML.parse(c))

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

export Config, configure, option
