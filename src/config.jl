using DataStructures: OrderedDict, DefaultOrderedDict
const _Config = OrderedDict{Symbol,Any}
"""
    Config

Contains a set of configuration for systems. Configuration for a system contains parameter values.

# Examples
```julia-repl
julia> @config :S => :a => 1
Config for 1 system:
  S
    a = 1
```

See also: [`@config`](@ref)
"""
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
            printstyled(x, rpad(canonicalnamelabel(k), l), color=:light_blue)
            printstyled(x, " = ", color=:light_black)
            print(x, labelstring(v))
        end
        String(take!(b))
    end
    color = get(io, :color, false)
    join(io, f.(c; color), '\n')
end

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
_configure(S::Type{<:System}, l) = begin
    P = filter(istag(:parameter), [n.info for n in dependency(S).N])
    K = map(v -> (v.name, v.alias), P) |> Iterators.flatten
    C = _configure(l)
    for k in keys(C)
        (k ∉ K) && error("unrecognized parameter: $S => $k")
    end
    _configure(namefor(S), C)
end
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

option(c::Config, s::Symbol, k::Symbol) = begin
    v = get(c, s, missing)
    ismissing(v) ? v : get(v, k, missing)
end
option(c::Config, S::Vector{Symbol}, k::Symbol) = option(c, S, [k])
option(c::Config, s::Symbol, K::Vector{Symbol}) = option(c, [s], K)
option(c::Config, S::Vector{Symbol}, K::Vector{Symbol}) = begin
    v = missing
    for (s, k) in Iterators.product(S, K)
        #HACK: support private parameter (i.e. :S => :_a for S._a)
        k = uncanonicalname(k, s)
        v = option(c, s, k)
        !ismissing(v) && break
    end
    v
end

using DataStructures: OrderedSet
"""
    parameters(S; <keyword arguments>) -> Config

Extract a list of parameters defined for system `S`.

# Arguments
- `S::Type{<:System}`: type of system to be inspected.

# Keyword Arguments
- `alias=false`: show alias instead of parameter name.
- `recursive=false`: extract parameters from other systems declared in `S`.
- `exclude=()`: systems excluded in recurisve search.
- `scope=nothing`: evaluation scope; default is `S.name.module`.

# Examples
```julia-repl
julia> @system S(Controller) begin
           a: aaa => 1 ~ preserve(parameter)
       end;

julia> parameters(S)
Config for 1 system:
  S
    a = 1

julia> parameters(S; alias=true)
Config for 1 system:
  S
    aaa = 1

julia> parameters(S; recursive=true)
Config for 3 systems:
  Clock
    init = 0 hr
    step = 1 hr
  Context
  S
    a = 1

julia> parameters(S; recursive=true, exclude=(Context,))
Config for 1 system:
  S
    a = 1
```
"""
parameters(::Type{S}; alias=false, recursive=false, exclude=(), scope=nothing) where {S<:System} = begin
    #HACK: default evaluation scope is the module where S was originally defined
    isnothing(scope) && (scope = S.name.module)
    V = [n.info for n in dependency(S).N]
    P = filter(istag(:parameter), V)
    key = alias ? (v -> isnothing(v.alias) ? v.name : v.alias) : (v -> v.name)
    K = constsof(S) |> keys
    # evaluate only if parameter has no dependency on other variables
    val(v) = val(v, Val(isempty(v.args)))
    val(v, ::Val{false}) = missing
    val(v, ::Val{true}) = begin
        @gensym CS
        l = (:($k = $CS[$(Meta.quot(k))]) for k in K)
        b = @eval scope let $CS = Cropbox.constsof($S), $(l...); $(v.body) end
        u = @eval scope let $CS = Cropbox.constsof($S), $(l...); $(gettag(v, :unit)) end
        unitfy(b, u)
    end
    C = configure(namefor(S) => ((key(v) => val(v) for v in P)...,))
    if recursive
        T = OrderedSet([@eval scope $(v.type) for v in V])
        T = map(collect(T)) do t
            #HACK: not working for dynamic type (i.e. eltype(Vector{<:System}) = Any)
            et = eltype(t)
            et <: System ? et : t <: System ? t : nothing
        end
        filter!(!isnothing, T)
        filter!(t -> !any(t .<: exclude), T)
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
"""
    @config c.. -> Config | Vector{Config}

Construct a set or multiple sets of configuration.

A basic unit of configuration for a system `S` is represented by a pair in the form of `S => pv`. System name `S` is expressed in a symbol. If actual type of system is used, its name will be automatically converted to a symbol.
    
A parameter name and corresponding value is then represented by another pair in the form of `p => v`. When specifiying multiple parameters, a tuple of pairs like `(p1 => v1, p2 => v2)` or a named tuple like `(p1 = v1, p2 = v2)` can be used. Parameter name must be a symbol and should indicate a variable declared with `parameter` tag as often used by `preserve` state variable. For example, `:S => (:a => 1, :b => 2)` has the same meaning as `S => (a = 1, b = 2)` in the same scope.

Configurations for multiple systems can be concatenated by a tuple. Multiple elements in `c` separated by commas implicitly forms a tuple. For example, `:S => (:a => 1, :b => 2), :T => :x => 1` represents a set of configuration for two systems `S` and `T` with some parameters. When the same names of system or variable appears again during concatenation, it will be overriden by later ones in an order appeared in a tuple. For example, `:S => :a => 1, :S => :a => 2` results into `:S => :a => 2`. Instead of commas, `+` operator can be used in a similar way as `(:S => :a => 1) + (:S => :a => 2)`. Note parentheses placed due to operator precedence.

When multiple sets of configurations are needed, as in `configs` for [`simulate`](@ref), a vector of `Config` is used. This macro supports some convenient ways to construct a vector by composing simpler configurations. Prefix operator `!` allows *expansion* of any iterable placed in the configuration value. Infix operator `*` allows *multiplication* of a vector of configurations with another vector or a single configuration to construct multiple sets of configurations. For example, `!(:S => :a => 1:2)` is expanded into two sets of separate configurations `[:S => :a => 1, :S => :a => 2]`. `(:S => :a => 1:2) * (:S => :b => 0)` is multiplied into `[:S => (a = 1, b = 0), :S => (a = 2, b = 0)]`.

# Examples
```julia-repl
julia> @config :S => (:a => 1, :b => 2)
Config for 1 system:
  S
    a = 1
    b = 2
```

```julia-repl
julia> @config :S => :a => 1, :S => :a => 2
Config for 1 system:
  S
    a = 2
```

```julia-repl
julia> @config !(:S => :a => 1:2)
2-element Vector{Config}:
 <Config>
 <Config>
```

```julia-repl
julia> @config (:S => :a => 1:2) * (:S => :b => 0)
2-element Vector{Config}:
 <Config>
 <Config>
```
"""
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

export Config, parameters, @config
