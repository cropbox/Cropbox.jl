const Config = Dict{Any,Any}

configure(c::Dict) = Config(Symbol(p.first) => configure(p.second) for p in c)
configure(c::Tuple) = configure(Config(c))
configure(c::Pair...) = configure(Config(c...))
configure(c) = c

#TODO: wait until TOML 0.5 gets support
# using TOML
# loadconfig(c::AbstractString) = configure(TOML.parse(c))

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

import DataStructures: OrderedSet
parameters(::Type{S}) where {S<:System} = begin
    d = dependency(S)
    V = [n.info for n in d.N]
    #HACK: only extract parameters with no dependency on other variables
    filter!(v -> istag(v, :parameter) && isempty(v.args), V)
    configure(S => ((v.name => eval(v.body) for v in V)...))
end

export configure
