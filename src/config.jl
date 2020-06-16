import DataStructures: OrderedDict, DefaultOrderedDict
const Config = OrderedDict{Symbol,Any}

configure(c::AbstractDict) = configure(c...)
configure(c::Pair) = _configure(c.first, c.second)
configure(c::Tuple) = configure(c...)
configure(c::Vector) = error("single configuration expected: $c")
#HACK: allow single patch (i.e. `0 => :a => 1` instead of `1:2`) in configexpand
configure(c::Array{T,0}) where {T} = configure(c...)
configure(c...) = merge(merge, configure.(c)...)
configure(::Nothing) = configure()
configure(c) = error("unrecognized configuration: $c")
configure() = Config()
_configure(k::Symbol, v) = Config(k => _configure(v))
_configure(k::String, v) = begin
    a = Symbol.(split(k, "."))
    n = length(a)
    if n == 2
        Config(a[1] => _configure(a[2] => v))
    elseif n == 1
        Config(a[1] => _configure(v))
    else
        error("unrecognized configuration key string: $k")
    end
end
_configure(k::Type{<:System}, v) = _configure(nameof(k), v)
_configure(k, v) = _configure(Symbol(k), v)
_configure(v) = Config(v)
_configure(v::NamedTuple) = Config(pairs(v))

parameterflatten(c::Config) = begin
    l = OrderedDict()
    for (s, d) in c
        for (k, v) in d
            l[(s, k)] = v
        end
    end
    l
end
parameterkeys(c::Config) = collect(keys(parameterflatten(c)))
parametervalues(c::Config) = collect(values(parameterflatten(c)))
parameterzip(K, V) = begin
    l = DefaultOrderedDict(OrderedDict)
    for ((s, k), v) in zip(K, V)
        l[s][k] = v
    end
    configure(l)
end

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
parameters(::Type{S}; alias=false, recursive=false, exclude=(), scope=nothing) where {S<:System} = begin
    #HACK: default evaluation scope is the module where S was originally defined
    isnothing(scope) && (scope = S.name.module)
    V = [n.info for n in dependency(S).N]
    P = filter(v -> istag(v, :parameter), V)
    key = alias ? (v -> isnothing(v.alias) ? v.name : v.alias) : (v -> v.name)
    # evaluate only if parameter has no dependency on other variables
    val(v) = val(v, Val(isempty(v.args)))
    val(v, ::Val{false}) = missing
    val(v, ::Val{true}) = begin
        b = @eval scope $(v.body)
        u = @eval scope $(v.tags[:unit])
        unitfy(b, u)
    end
    C = configure(nameof(S) => ((key(v) => val(v) for v in P)...,))
    if recursive
        T = OrderedSet([@eval scope $(v.type) for v in V])
        T = filter(t -> t <: System && t ∉ exclude, T)
        X = (S, T..., exclude...) |> Set
        C = configure(parameters.(T, alias=alias, recursive=true, exclude=X, scope=scope)..., C)
    end
    C
end

configmultiply(; base=()) = [configure(base)]
configmultiply(patches::Vector; base=()) = configmultiply(patches...; base=base)
configmultiply(patches...; base=()) = begin
    C = configexpand(patches[1]; base=base)
    for p in patches[2:end]
        C = [configexpand(p; base=c) for c in C] |> Iterators.flatten |> collect
    end
    C
end
configexpand(patch; base=()) = begin
    P = configure(patch)
    configs = if isempty(P)
        []
    else
        s, C = only(P)
        k, V = only(C)
        [s => k => v for v in V]
    end
    configrebase(configs; base=base)
end
configrebase(configs::Vector; base=()) = isempty(configs) ? [configure(base)] : [configure((base, c)) for c in configs]
configrebase(config; base=()) = configrebase([config]; base=base)

configreduce(a::Vector, b) = configrebase(b; base=a)
configreduce(a, b::Vector) = configrebase(b; base=a)
configreduce(a, b) = configure(a, b)

macro config(ex)
    @capture(ex, +(P__) | P__)
    P = map(P) do p
        if @capture(p, !x_)
            :(Cropbox.configexpand($(esc(x))))
        elseif @capture(p, *(x__))
            :(Cropbox.configmultiply($(esc.(x)...)))
        else
            esc(p)
        end
    end
    reduce(P) do a, b
        :(Cropbox.configreduce($a, $b))
    end
end

export configure, parameters, @config
