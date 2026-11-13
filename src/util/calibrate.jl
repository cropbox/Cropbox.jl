using DataStructures: OrderedDict
import DataFrames
import Random
import BlackBoxOptim

"""
    calibrate(S, obs; <keyword arguments>) -> Config | OrderedDict

Obtain a set of parameters for the given system `S` that simulates provided observation `obs` closely as possible. A multitude of simulations are conducted with a differing combination of parameter sets specified by the range of possible values and the optimum is selected based on a choice of evaluation metric. Internally, differential evolution algorithm from BlackboxOptim.jl is used.

# Arguments
- `S::Type{<:System}`: type of system to be calibrated.
- `obs::DataFrame`: observation data to be used for calibration.

# Keyword Arguments
## Configuration
- `config=()`: a single base configuration for the system (can't be used with `configs`).
- `configs=[]`: multiple base configurations for the system (can't be used with `config`).

## Layout
- `index=nothing`: variables to construct index columns of the output; default falls back to `context.clock.time`.
- `target`: variables to construct non-index columns of the output.

## Calibration
- `parameters`: parameters with a range of boundary values to be calibrated within.
- `metric=nothing`: evaluation metric (`:rmse`, `:nrmse`, `:mae`, `:mape`, `:ef`, `:dr`); default is RMSE.
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
calibrate(S::Type{<:System}, obs::DataFrame; config=(), configs=[], kwargs...) = begin
    if isempty(configs)
        calibrate(S, obs, [config]; kwargs...)
    elseif isempty(config)
        calibrate(S, obs, configs; kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
calibrate(S::Type{<:System}, obs::DataFrame, configs::Vector; index=nothing, target, parameters, metric=nothing, weight=nothing, pareto=false, optim=(), warn = true, kwargs...) = begin
    P = configure(parameters)
    K = parameterkeys(P)
    V = parametervalues(P)
    U = parameterunits(resolveparameters(parameters, S))
    I = parseindex(index, S) |> keys |> collect
    T = parsetarget(target, S) |> keys |> collect
    obs = filterobservations(obs, T)
    n = length(T)
    multi = n > 1
    isnothing(metric) && (metric = :rmse)
    metric = metricfunc(metric)
    IC = [t for t in zip(getproperty.(Ref(obs), I)...)]
    IV = parseindex(index, S) |> values |> Tuple
    snap(s) = indexcontains(getproperty.(s, IV) .|> value, IC)
    residual(c, rows) = begin
        est = simulate(S; config=c, index, target, snap, verbose=false, kwargs...)
        isempty(est) && return repeat([Inf], n)
        O, E = aligndata(obs, est, T; index = I, allowempty = true, rows)
        isempty(first(O)) && return repeat([Inf], n)
        [metric(e, o) for (o, e) in zip(O, E)]
    end
    config(X) = parameterzip(K, X, U)
    cost(X) = begin
        c = config(X)
        l = length(configs)
        R = Vector(undef, l)
        rows = warn ? [Int[] for _ in 1:l] : fill(nothing, l)
        Threads.@threads for i in 1:l
            R[i] = residual(configure(configs[i], c), rows[i])
        end
        A = eachrow(hcat(R...)) .|> Iterators.flatten .|> collect |> deunitfy
        e = eachrow(hcat(A...)) |> sum
        # BlackBoxOptim expects Float64, not even Int
        e = Float64.(e)
        if warn && all(isfinite, e)
            if warnmatching(obs, Iterators.flatten(rows); context = "calibration candidate (shown once per search)")
                warn = false
            end
        end
        multi ? Tuple(e) : e[1]
    end
    range = map((p, u) -> Float64.(Tuple(deunitfy(p, u))), V, U)
    method = if multi
        agg = isnothing(weight) ? mean : let w = StatsBase.weights(weight); f -> mean(f, w) end
        (Method=:borg_moea, FitnessScheme=BlackBoxOptim.ParetoFitnessScheme{n}(aggregator=agg))
    else
        ()
    end
    optim_default = (;
        MaxSteps=5000,
        TraceInterval=10,
    )
    #HACK: initialize random seed before calling BlackBoxOptim
    # https://github.com/robertfeldt/BlackBoxOptim.jl/issues/158
    Random.seed!(0)
    r = BlackBoxOptim.bboptimize(cost;
        SearchRange=range,
        method...,
        optim_default...,
        optim...
    )
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
