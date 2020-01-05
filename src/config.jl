import DataStructures: OrderedDict
const Config = OrderedDict{Any,Any}

configure(c::AbstractDict) = Config(Symbol(p.first) => configure(p.second) for p in c)
configure(c::Tuple) = configure(Config(c))
configure(c::Pair) = configure(Config(c))
configure(c...) = merge(merge, configure.(c)...)
configure(c) = c

#TODO: wait until TOML 0.5 gets support
# using TOML
# loadconfig(c::AbstractString) = configure(TOML.parse(c))

option(c) = c
option(c, keys...) = missing
option(c::Config, key::Symbol, keys...) = option(get(c, key, missing), keys...)
option(c::Config, key::Vector{Symbol}, keys...) = begin
    for k in key
        v = option(c, k, keys...)
        !ismissing(v) && return v
    end
    missing
end

import DataStructures: OrderedSet
parameters(::Type{S}; recursive=false) where {S<:System} = begin
    V = [n.info for n in dependency(S).N]
    #HACK: only extract parameters with no dependency on other variables
    P = filter(v -> istag(v, :parameter) && isempty(v.args), V)
    C = configure(nameof(S) => ((v.name => unitfy(eval(v.body), eval(v.tags[:unit])) for v in P)...,))
    if recursive
        #HACK: evaluate types defined in Main module
        T = OrderedSet([Main.eval(v.type) for v in V])
        T = filter(t -> t <: System, T)
        C = configure(parameters.(T, recursive=true)..., C)
    end
    C
end
