import GlobalSensitivity

analyzemethod(method::Symbol) = begin
    constructors = (; morris = GlobalSensitivity.Morris, sobol = GlobalSensitivity.Sobol, efast = GlobalSensitivity.eFAST)
    hasproperty(constructors, method) || throw(ArgumentError("unsupported sensitivity method: $method"))
    getproperty(constructors, method)()
end
analyzemethod(method) = method

checkgsa(method, options) = begin
    allowed = if method isa GlobalSensitivity.Morris
        method.num_trajectory > 0 && method.total_num_trajectory >= method.num_trajectory && method.len_design_mat > 1 ||
            throw(ArgumentError("Morris requires positive retained trajectories, at least as many candidates, and at least two points per trajectory"))
        (:rng, :batch)
    elseif method isa GlobalSensitivity.Sobol
        method.nboot > 0 || throw(ArgumentError("Sobol nboot must be positive"))
        get(options, :Ei_estimator, :Jansen1999) in (:Homma1996, :Sobol2007, :Jansen1999, :Janon2014) ||
            throw(ArgumentError("unsupported Sobol Ei_estimator"))
        (:samples, :Ei_estimator, :batch)
    elseif method isa GlobalSensitivity.eFAST
        method.num_harmonics > 0 || throw(ArgumentError("eFAST num_harmonics must be positive"))
        (:samples, :rng, :batch)
    else
        throw(ArgumentError("unsupported sensitivity method: $method"))
    end
    for k in keys(options)
        k in allowed || throw(ArgumentError("unsupported gsa option $k for $(nameof(typeof(method))); configure method options on the method object"))
    end
    get(options, :batch, false) === false || throw(ArgumentError("analyze does not support batch evaluation"))
    if !(method isa GlobalSensitivity.Morris)
        n = get(options, :samples, nothing)
        n isa Integer && !(n isa Bool) && n > 0 || throw(ArgumentError("gsa.samples must be a positive integer"))
        method isa GlobalSensitivity.eFAST && n <= 4 * method.num_harmonics^2 &&
            throw(ArgumentError("eFAST requires samples > 4 * num_harmonics^2"))
    end
end

"""
    analyze(S; target, parameters, stop, method=:morris, gsa=(), kwargs...)
    analyze(f, S; target, parameters, stop, method=:morris, gsa=(), kwargs...)

Analyze the sensitivity of a model's endpoint, or a scalar summary `f(df)` of
each newly simulated DataFrame. Returns `(table, raw)` as a named tuple.

`method` accepts `:morris`, `:sobol`, `:efast`, or the corresponding
GlobalSensitivity method object. Constructor options belong on that object;
execution options belong in `gsa`, e.g. `gsa = (; samples = 1024)` for Sobol or
eFAST, or `gsa = (; rng = Random.Xoshiro(42))` for Morris. Unsupported execution
options and batch evaluation are rejected rather than silently ignored.

`parameters` contains finite lower/upper bounds for independently varied,
continuous parameters. Sampling uses a unit box mapped to those bounds, so
Morris effects are per full parameter range, not per physical input unit.
Morris effects retain output units; Sobol/eFAST indices are dimensionless.

Use `config` or `configs`, not both. Every condition is evaluated at the same
sampled parameter sets; conditions and targets remain separate in `table`.
The raw output order is configuration first, then target, matching the table.
The callback must return one finite real value, optionally with units; its
output is named `:summary`. It receives a fresh DataFrame on every model run,
not a previously stored trajectory. `stop` is required (`stop = 0` for static
models). Endpoint analysis reads the final model state even if `snap` omits it.

`base`, `options`, and `seed` follow `simulate`; other keywords are forwarded to
`simulate!`. Endpoint analysis disables snapshots by default; callbacks retain
the normal snapshot behavior. `raw` preserves the original GlobalSensitivity
result, including interactions and confidence information not shown in `table`.

See also: [`simulate`](@ref), [`evaluate`](@ref), [`calibrate`](@ref)
"""
analyze(S::Type{<:System}; kw...) = analyze(nothing, S; kw...)
analyze(summarize::Union{Function,Nothing}, S::Type{<:System};
    target, parameters, stop,
    config = (), configs = [], base = nothing, options = (), seed = nothing,
    method = :morris, gsa = (), kw...
) = begin
    isnothing(stop) && throw(ArgumentError("specify stop explicitly; use stop = 0 for a static model"))
    method = deepcopy(analyzemethod(method))
    gsa = deepcopy((; gsa...))
    checkgsa(method, gsa)
    isempty(config) || isempty(configs) || throw(ArgumentError("config and configs cannot be used together"))
    C = isempty(configs) ? [configure(config)] : configure.(configs)
    P = configure(((k == Symbol(0) ? namefor(S) : k) => v for (k, v) in configure(parameters))...)
    K = parameterkeys(P)
    isempty(K) && throw(ArgumentError("specify at least one varying parameter"))
    if method isa GlobalSensitivity.Morris && !isempty(method.p_steps)
        length(method.p_steps) == length(K) && all(>(1), method.p_steps) ||
            throw(ArgumentError("Morris p_steps must contain one grid size greater than one per parameter"))
    end
    identities = Tuple{Symbol,Symbol}[]
    U = map(K) do (system, key)
        type = system == namefor(S) ? S : typefor(system, scopeof(S))
        name = canonicalname(key, system)
        vars = [v.info for v in dependency(type).N]
        i = findfirst(v -> istag(v, :parameter) && name in names(v), vars)
        isnothing(i) && throw(ArgumentError("not a parameter: $system.$key"))
        id = (system, vars[i].name)
        id in identities && throw(ArgumentError("parameter specified more than once through an alias: $system.$key"))
        push!(identities, id)
        eltype(vartype(type, name)) <: Union{Integer,Quantity{<:Integer}} &&
            throw(ArgumentError("analyze requires continuous parameters: $system.$key"))
        fieldunit(type, name)
    end
    # https://github.com/SciML/GlobalSensitivity.jl/issues/229; remove after the upstream fix.
    if method isa GlobalSensitivity.eFAST && length(K) == 2 && (gsa.samples - 1) ÷ (4 * method.num_harmonics^2) > 1
        throw(ArgumentError("this eFAST sample count hits GlobalSensitivity.jl#229 with two parameters; use Morris or Sobol"))
    end
    bounds = map(parametervalues(P), U) do v, u
        (v isa Tuple || v isa AbstractVector) && length(v) == 2 ||
            throw(ArgumentError("each parameter requires a (lower, upper) pair"))
        lo, hi = Float64.(deunitfy(v, u))
        isfinite(lo) && isfinite(hi) && lo < hi && isfinite(hi - lo) ||
            throw(ArgumentError("parameter bounds must be finite and increasing; put fixed values in config"))
        (lo, hi)
    end
    lower, width = first.(bounds), last.(bounds) .- first.(bounds)
    isnothing(target) && throw(ArgumentError("specify concrete scalar targets"))
    T = parsetarget(target, S)
    isempty(T) && throw(ArgumentError("specify at least one target"))
    any(v -> v isa AbstractString && occursin('*', v), values(T)) &&
        throw(ArgumentError("analyze requires concrete scalar targets, not wildcards"))
    targets = isnothing(summarize) ? collect(keys(T)) : [:summary]
    n = length(targets) * length(C)
    units = Any[]
    minima, maxima = fill(Inf, n), fill(-Inf, n)
    run(X) = begin
        sampled = parameterzip(K, lower .+ X .* width, U)
        Y = Any[]
        for (i, c) in enumerate(C)
            s = instance(S; config = configure(c, sampled), options, seed)
            snap = isnothing(summarize) ? false : nothing
            df = simulate!(s; base, target, stop, snap, verbose = false, kw...)
            if isnothing(summarize)
                append!(Y, [value(s[base][v]) for v in values(T)])
            else
                isempty(df) && throw(ArgumentError("no snapshots to summarize for config $i"))
                push!(Y, summarize(df))
            end
        end
        all(y -> y isa Number, Y) || throw(ArgumentError("analysis outputs must be real scalars, optionally with units"))
        isempty(units) && append!(units, [isnothing(u) ? nothing : Unitful.absoluteunit(u) for u in unittype.(Y)])
        V = deunitfy.(Y, units)
        all(v -> v isa Real, V) || throw(ArgumentError("analysis outputs must be real scalars"))
        V = Float64.(V)
        all(isfinite, V) || throw(ArgumentError("analysis outputs must be finite in Float64"))
        minima .= min.(minima, V)
        maxima .= max.(maxima, V)
        V
    end
    raw = GlobalSensitivity.gsa(run, method, fill((0.0, 1.0), length(K)); gsa...)
    if !(method isa GlobalSensitivity.Morris) && any(minima .== maxima)
        throw(ArgumentError("variance-based sensitivity is undefined for a constant sampled output"))
    end
    estimates = method isa GlobalSensitivity.Morris ? (raw.means, raw.means_star, raw.variances) : (raw.S1, raw.ST)
    all(a -> all(isfinite, a), estimates) || throw(ArgumentError("non-finite sensitivity estimates; check method settings and sampled outputs"))
    table = DataFrame(
        config = repeat(collect(1:length(C)); inner = length(targets), outer = length(K)),
        target = repeat(targets, length(C) * length(K)),
        system = repeat(first.(K); inner = n), parameter = repeat(last.(K); inner = n),
        lower = repeat(unitfy.(lower, U); inner = n), upper = repeat(unitfy.(last.(bounds), U); inner = n))
    if method isa GlobalSensitivity.Morris
        u = repeat(method.relative_scale ? fill(nothing, n) : units, length(K))
        table.means = unitfy.(vec(raw.means), u)
        table.means_star = unitfy.(vec(raw.means_star), u)
        table.variances = unitfy.(vec(raw.variances), [isnothing(v) ? nothing : v^2 for v in u])
    else
        table.S1, table.ST = vec(raw.S1), vec(raw.ST)
    end
    (; table, raw)
end

export analyze
