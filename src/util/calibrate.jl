using DataStructures: OrderedDict
import DataFrames
import BlackBoxOptim

"""
    calibrate(S, obs; <keyword arguments>) -> Config | OrderedDict
    calibrate(S, [obs1, obs2, …]; <keyword arguments>) -> Config | OrderedDict

Obtain a set of parameters for the given system `S` that simulates provided observation `obs` closely as possible. A multitude of simulations are conducted with a differing combination of parameter sets specified by the range of possible values and the optimum is selected based on a choice of evaluation metric. Internally, differential evolution algorithm from BlackboxOptim.jl is used.

# Arguments
- `S::Type{<:System}`: type of system to be calibrated.
- `obs`: one observation table (or view), a grouped data frame, or a vector of tables for experiments sharing the parameters being fitted.

# Keyword Arguments
## Configuration
- `config=()`: one base configuration for all observation tables (can't be used with `configs`).
- `configs=nothing`: a vector of base configurations. One observation table is shared unless `match` is given; a vector of tables is paired in order.
- `match=nothing`: pair experiments by label, e.g. `:Trial => :site` or `:Trial => [:site, :year]`. The section is read from each config and the columns from the observation table. For a grouped data frame, just name the section.

## Layout
- `base=nothing`: subsystem from which both the index and target are read.
- `index=nothing`: variables to construct index columns of the output; default falls back to `context.clock.time`.
- `target`: variables to construct non-index columns of the output.
- `meta=nothing`: additional columns in simulated output, as in `simulate`; not used to pair experiments.

## Calibration
- `parameters`: parameters with a range of boundary values to be calibrated within.
- `seed=0`: start the optimizer once and each candidate's simulation with this seed. Use `nothing` to draw fresh model seeds from the caller's random stream.
- `metric=nothing`: objective to minimize (default `:rmse`; other error metrics: `:nrmse`, `:rmspe`, `:mae`, `:mape`).
  Do not minimize `:ef` or `:dr` directly: larger values are better. For a higher-is-better
  function `score`, pass a loss such as `(E, O) -> 1 - score(E, O)` instead.
- `warn=true`: warn once per search about partial observation matching.

## Multi-objective
- `weight=nothing`: weights for calibrating multiple targets; default assumes equal weights.
- `pareto=false`: returns a dictionary containing Pareto frontier instead of a single solution satisfying multiple targets.

## Advanced
- `optim=()`: extra options for `BlackBoxOptim.bboptimize`.

Remaining keyword arguments are passed down to `simulate` with regard to running system `S`.
Rows missing any requested observation target are omitted before the search.
An `ArgumentError` is raised if no complete observations or no finite result remain.
Partial matches warn once per search, with counts for the first finite candidate
that uses only part of the complete observations.
Parameter names and units are resolved against the model's declared systems and
mixins. For dynamic children whose types are not known, an explicit system type
or a name resolved in the model's modules or `Main` supplies the parameter definition.
Its existence and unit are checked, but unverified participation is reported once
before optimization. Unknown or ambiguous names, non-parameters and duplicate
targets raise an `ArgumentError`. The key `:0` selects the root system.

See also: [`simulate`](@ref), [`evaluate`](@ref), [`@config`](@ref)

# Examples
```julia-repl
julia> @system S(Controller) begin
           a => 0 ~ preserve(parameter)
           b(a) ~ accumulate
       end;

julia> obs = DataFrame(time=10u"hr", b=200);

julia> p = calibrate(S, obs; target=:b, parameters=:S => :a => (0, 100), stop=10)
...
Config for 1 system:
  S
    a = 20.0
```
"""
calibrate(S::Type{<:System}, obs::AbstractDataFrame; config = (), configs = nothing, match = nothing, kw...) = begin
    cs = isnothing(match) && (isnothing(configs) || isempty(configs)) ? [config] : checkconfigs(config, configs)
    calibrate(S, obs, cs; match, kw...)
end
calibrate(S::Type{<:System}, obs::AbstractDataFrame, configs::Vector; match = nothing, kw...) = begin
    if isnothing(match)
        _calibrate(S, (obs,), configs, fill(1, length(configs)); kw...)
    else
        match isa Pair || throw(ArgumentError("match must specify a configuration section => observation column(s), e.g. :Trial => :site"))
        section, cols = match
        groups = DataFrames.groupby(obs, cols; sort = false)
        calibrate(S, groups, configs; match = section, kw...)
    end
end

calibrate(S::Type{<:System}, groups::DataFrames.GroupedDataFrame; config = (), configs = nothing, match = nothing, kw...) = begin
    if isnothing(configs) && isnothing(match)
        calibrate(S, collect(AbstractDataFrame, groups); config, kw...)
    else
        calibrate(S, groups, checkconfigs(config, configs); match, kw...)
    end
end
calibrate(S::Type{<:System}, groups::DataFrames.GroupedDataFrame, configs::Vector; match = nothing, kw...) =
    calibrate(S, matchgroups(groups, configs, match), configs; kw...)

calibrate(S::Type{<:System}, obss::AbstractVector{<:AbstractDataFrame}; config = (), configs = nothing, kw...) = begin
    cs = isnothing(configs) ? fill(config, length(obss)) : checkconfigs(config, configs)
    calibrate(S, obss, cs; kw...)
end
calibrate(S::Type{<:System}, obss::AbstractVector{<:AbstractDataFrame}, configs::Vector; match = nothing, kw...) = begin
    isnothing(match) || throw(ArgumentError("a vector of observation tables is already paired with configs in order; omit match"))
    length(obss) == length(configs) || throw(ArgumentError("expected one configuration per observation table, got $(length(configs)) for $(length(obss)) tables"))
    _calibrate(S, obss, configs, eachindex(configs); kw...)
end

checkconfigs(config, configs) = begin
    configs isa Vector || throw(ArgumentError("configs must be a vector of configurations"))
    isempty(config) || throw(ArgumentError("config and configs cannot be used together"))
    configs
end

matchgroups(groups, configs, section) = begin
    section isa Union{Symbol,AbstractString} || throw(ArgumentError("for grouped observations, name the configuration section with match (e.g. match = :Trial)"))
    cols = Tuple(DataFrames.groupcols(groups))
    isempty(cols) && throw(ArgumentError("match needs at least one observation column"))
    seen, tables = Set{Tuple}(), AbstractDataFrame[]
    for c in configs
        labels = get(configure(c), Symbol(section), (;))
        key = map(cols) do k
            v = get(labels, k, missing)
            ismissing(v) && throw(ArgumentError("missing configuration label $section.$k"))
            v
        end
        key in seen && throw(ArgumentError("duplicate configuration for observation group $key"))
        haskey(groups, key) || throw(ArgumentError("no observations for configuration group $key"))
        push!(seen, key)
        push!(tables, groups[key])
    end
    for key in keys(groups)
        Tuple(key) in seen || throw(ArgumentError("no configuration for observation group $(NamedTuple(key))"))
    end
    tables
end

_calibrate(S, obss, configs, tableids;
    base = nothing, index = nothing, target, parameters, metric = nothing, weight = nothing, pareto = false, optim = (), seed = 0, warn = true, kwargs...
) = begin
    isempty(configs) && throw(ArgumentError("at least one calibration experiment is required"))
    P = configure(parameters)
    K = parameterkeys(P)
    V = parametervalues(P)
    U = parameterunits(resolveparameters(parameters, S))
    IKV = parseindex(index, S)
    I = collect(keys(IKV))
    T = parsetarget(target, S) |> keys |> collect
    tables = map(obss) do obs
        obs = filterobservations(obs, T)
        (; obs, snap = observationsnap(obs, IKV, base))
    end
    total = sum(t -> nrow(t.obs), tables)
    n = length(T)
    multi = n > 1
    isnothing(metric) && (metric = :rmse)
    metric = metricfunc(metric)
    residual(c, table, rows, modelseed) = begin
        est = simulate(S; config = c, base, index, target, snap = table.snap, seed = modelseed, verbose = false, kwargs...)
        isempty(est) && return repeat([Inf], n)
        O, E = aligndata(table.obs, est, T; index = I, allowempty = true, rows)
        isempty(first(O)) && return repeat([Inf], n)
        [metric(e, o) for (o, e) in zip(O, E)]
    end
    config(X) = parameterzip(K, X, U)
    cost(X) = begin
        c = config(X)
        l = length(configs)
        R = Vector(undef, l)
        rows = warn ? [Int[] for _ in 1:l] : fill(nothing, l)
        # draw in configuration order, independent of worker scheduling
        seeds = isnothing(seed) ? rand(UInt64, l) : nothing
        Threads.@threads for i in 1:l
            R[i] = residual(configure(configs[i], c), tables[tableids[i]], rows[i], isnothing(seeds) ? seed : seeds[i])
        end
        A = eachrow(hcat(R...)) .|> Iterators.flatten .|> collect |> deunitfy
        e = eachrow(hcat(A...)) |> sum
        # BlackBoxOptim expects Float64, not even Int
        e = Float64.(e)
        if warn && all(isfinite, e)
            matched = length(Set((id, row) for (id, rs) in zip(tableids, rows) for row in rs))
            if warnmatching(matched, total; context = "calibration candidate (shown once per search)")
                warn = false
            end
        end
        multi ? Tuple(e) : e[1]
    end
    range = map((p, u) -> Float64.(Tuple(deunitfy(p, u))), V, U)
    method = if multi
        agg = isnothing(weight) ? mean : let w = StatsBase.weights(weight); x -> mean(collect(x), w) end
        (Method=:borg_moea, FitnessScheme=BlackBoxOptim.ParetoFitnessScheme{n}(aggregator=agg))
    else
        ()
    end
    optim_default = (;
        MaxSteps=5000,
        TraceInterval=10,
    )
    # BlackBoxOptim draws from the current task's RNG.
    r = withseed(seed) do
        BlackBoxOptim.bboptimize(cost; SearchRange = range, method..., optim_default..., optim...)
    end
    all(isfinite, BlackBoxOptim.best_fitness(r)) ||
        throw(ArgumentError("no finite calibration result; check observation indices, stop, snap, and the metric"))
    if multi && pareto
        pf = BlackBoxOptim.pareto_frontier(r)
        OrderedDict(BlackBoxOptim.fitness.(pf) .=> config.(BlackBoxOptim.params.(pf)))
    else
        config(BlackBoxOptim.best_candidate(r))
    end
end

export calibrate
