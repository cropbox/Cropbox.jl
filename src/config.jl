using DataStructures: OrderedDict, DefaultOrderedDict
const _Config = OrderedDict{Symbol,Any}
struct Config
    config::_Config
    Config(c...) = new(_Config(c...))
end

Base.getindex(c::Config, i) = c.config[i]
#HACK: handle :0
Base.getindex(c::Config, i::Int) = c.config[Symbol(i)]
Base.length(c::Config) = length(c.config)
Base.iterate(c::Config) = iterate(c.config)
Base.iterate(c::Config, i) = iterate(c.config, i)
Base.eltype(::Type{Config}) = Pair{Symbol,Any}

Base.get(c::Config, k, d) = get(c.config, k, d)
Base.haskey(c::Config, k) = haskey(c.config, k)

Base.:(==)(c::Config, d::Config) = c.config == d.config

Base.merge(f::Function, c::Config, D...) = merge(f, c.config, [d.config for d in D]...) |> Config

Base.show(io::IO, c::Config) = print(io, "<Config>")
Base.show(io::IO, ::MIME"text/plain", c::Config) = begin
    n = length(c)
    if n == 0
        print(io, "Config empty")
    elseif n == 1
        println(io, "Config for $n system:")
    else
        println(io, "Config for $n systems:")
    end
    f((s, C); color) = begin
        b = IOBuffer()
        x = IOContext(b, :color => color)
        print(x, "  ")
        printstyled(x, s, color=:light_magenta)
        K = keys(C)
        l = isempty(K) ? 0 : maximum(length.(string.(K)))
        for (k, v) in C
            println(x)
            print(x, "    ")
            printstyled(x, rpad(k, l), color=:light_blue)
            printstyled(x, " = ", color=:light_black)
            print(x, labelstring(v))
        end
        String(take!(b))
    end
    color = get(io, :color, false)
    join(io, f.(c; color), '\n')
end

@nospecialize

configure(c::Config) = c
configure(c::AbstractDict) = configure(c...)
configure(c::Pair) = _configure(c.first, c.second)
configure(c::Tuple) = configure(c...)
configure(c::Vector) = configure.(c)
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
_configure(k::Type{<:System}, v) = _configure(namefor(k), v)
_configure(k, v) = _configure(Symbol(k), v)
_configure(v) = _Config(v)
_configure(v::NamedTuple) = _Config(pairs(v))

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
option(c::Config, keys...) = option(c.config, keys...)
option(c::_Config, key::Symbol, keys...) = option(get(c, key, missing), keys...)
option(c::_Config, key::Vector{Symbol}, keys...) = begin
    for k in key
        v = option(c, k, keys...)
        !ismissing(v) && return v
    end
    missing
end

using DataStructures: OrderedSet
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
        u = @eval scope $(gettag(v, :unit))
        unitfy(b, u)
    end
    C = configure(namefor(S) => ((key(v) => val(v) for v in P)...,))
    if recursive
        T = OrderedSet([@eval scope $(v.type) for v in V])
        T = filter(t -> t <: System && t ∉ exclude, T)
        X = (S, T..., exclude...) |> Set
        C = configure(parameters.(T; alias, recursive=true, exclude=X, scope)..., C)
    end
    C
end
#TODO: parameters(::System) to show current configurations (need proper handling of alias)

configmultiply(; base=()) = [configure(base)]
configmultiply(patches::Vector; base=()) = configmultiply(patches...; base)
configmultiply(patches...; base=()) = begin
    C = configexpand(patches[1]; base)
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
        #HACK: allow single patch (i.e. `0 => :a => 1` instead of `1:2`)
        reshape([s => k => v for v in V], :)
    end
    configexpand(configs; base)
end
configexpand(configs::Vector; base=()) = configrebase(configs; base)
configrebase(configs::Vector; base=()) = isempty(configs) ? [configure(base)] : [configure(base, c) for c in configs]
configrebase(config; base=()) = configrebase([config]; base)

configreduce(a::Vector, b) = configure.(a, b)
configreduce(a, b::Vector) = configrebase(b; base=a)
configreduce(a::Vector, b::Vector) = configreduce.(a, b)
configreduce(a, b) = configure(a, b)
configreduce(a) = configure(a)
configreduce(a::Vector) = configure.(a)

using MacroTools: @capture
macro config(ex)
    @capture(ex, +(P__) | P__)
    P = map(P) do p
        if @capture(p, !x_)
            :(Cropbox.configexpand($(esc(x))))
        elseif @capture(p, *(x__))
            :(Cropbox.configmultiply($(esc.(x)...)))
        else
            :(Cropbox.configreduce($(esc(p))))
        end
    end
    reduce(P) do a, b
        :(Cropbox.configreduce($a, $b))
    end
end

macro config(ex, exs...)
    :(Cropbox.@config(($(esc(ex)), $(esc.(exs)...))))
end

macro config()
    :(Cropbox.@config(()))
end

@specialize

export configure, parameters, @config
