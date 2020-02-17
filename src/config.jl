import DataStructures: OrderedDict
const Config = OrderedDict{Any,Any}

configure(c::AbstractDict) = configure(c...)
configure(c::Pair) = _configure(c.first, c.second)
configure(c::Tuple) = configure(c...)
configure(c...) = merge(merge, configure.(c)...)
configure() = Config()
_configure(k::Symbol, v) = Config(k => _configure(v))
_configure(k::Type{<:System}, v) = _configure(nameof(k), v)
_configure(v) = Config(v)
_configure(v::NamedTuple) = Config(pairs(v))

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
parameters(::Type{S}; alias=false, recursive=false, exclude=()) where {S<:System} = begin
    V = [n.info for n in dependency(S).N]
    #HACK: only extract parameters with no dependency on other variables
    P = filter(v -> istag(v, :parameter) && isempty(v.args), V)
    key = alias ? (v -> isnothing(v.alias) ? v.name : v.alias) : (v -> v.name)
    C = configure(nameof(S) => ((key(v) => unitfy(Main.eval(v.body), Main.eval(v.tags[:unit])) for v in P)...,))
    if recursive
        #HACK: evaluate types defined in Main module
        T = OrderedSet([Main.eval(v.type) for v in V])
        T = filter(t -> t <: System && t ∉ exclude, T)
        X = (S, T..., exclude...) |> Set
        C = configure(parameters.(T, alias=alias, recursive=true, exclude=X)..., C)
    end
    C
end
