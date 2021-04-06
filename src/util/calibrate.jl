using DataStructures: OrderedDict
import DataFrames
using StatsBase: StatsBase, mean
import Random
import BlackBoxOptim

metricfunc(metric::Symbol) = begin
    if metric == :rmse
        (E, O) -> √mean((E .- O).^2)
    elseif metric == :nrmse
        (E, O) -> √mean((E .- O).^2) / mean(O)
    elseif metric == :rmspe
        (E, O) -> √mean(((E .- O) ./ O).^2)
    elseif metric == :mae
        (E, O) -> mean(abs.(E .- O))
    elseif metric == :mape
        (E, O) -> mean(abs.((E .- O) ./ O))
    # Nash-Sutcliffe model efficiency coefficient (NSE)
    elseif metric == :ef
        (E, O) -> 1 - sum((E .- O).^2) / sum((O .- mean(O)).^2)
    # Willmott's refined index of agreement (d_r)
    elseif metric == :dr
        (E, O) -> let a = sum(abs.(E .- O)),
            b = 2sum(abs.(O .- mean(O)))
            a <= b ? 1 - a/b : b/a - 1
        end
    else
        error("unsupported metric: $metric")
    end
end
metricfunc(metric) = metric

#HACK: handle index columns with non-identical, but compatible units
# https://github.com/JuliaData/DataFrames.jl/issues/2486
normalize!(dfs::DataFrame...; on) = begin
    for i in on
        cols = getindex.(dfs, !, i)
        elts = eltype.(cols)
        t = promote_type(elts...)
        for (d, c, e) in zip(dfs, cols, elts)
            e != t && setindex!(d, convert.(t, c), !, i)
        end
    end
end

"""
    calibrate(S, obs; <keyword arguments>) -> Config | OrderedDict

Obtain a set of parameters for the given system `S` that simulates provided observation `obs` closely as possible. A multitude of simulations are conducted with a differing combination of parameter sets specified by the range of possible values and the optimum is selected based on a choice of evaluation metric. Internally, differential evolution algorithm from BlackboxOptim.jl is used.

# Arguments
- `S::Type{<:System}`: type of system to be calibrated.
- `obs::DataFrame`: observatioan data to be used for calibration.

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

## Multi-objective
- `weight=nothing`: weights for calibrating multiple targets; default assumes equal weights.
- `pareto=false`: returns a dictionary containing Pareto frontier instead of a single solution satisfying multiple targets.

## Advanced
- `optim=()`: extra options for `BlackBoxOptim.bboptimize`.

Remaining keyword arguments are passed down to `simulate` with regard to running system `S`.

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
calibrate(S::Type{<:System}, obs::DataFrame, configs::Vector; index=nothing, target, parameters, metric=nothing, weight=nothing, pareto=false, optim=(), kwargs...) = begin
    #HACK: use copy due to normalize!
    obs = copy(obs)
    P = configure(parameters)
    K = parameterkeys(P)
    I = parsesimulation(defaultindex(index, S)) |> keys |> collect
    T = parsesimulation(defaulttarget(target, S)) |> keys |> collect
    n = length(T)
    multi = n > 1
    isnothing(metric) && (metric = :rmse)
    metric = metricfunc(metric)
    IC = [t for t in zip(getproperty.(Ref(obs), I)...)]
    IV = parsesimulation(defaultindex(index, S)) |> values |> Tuple
    snap(s) = getproperty.(s, IV) .|> value in IC
    NT = DataFrames.make_unique([propertynames(obs)..., T...], makeunique=true)
    T1 = NT[end-n+1:end]
    residual(c) = begin
        est = simulate(S; config=c, index, target, snap, verbose=false, kwargs...)
        isempty(est) && return repeat([Inf], n)
        normalize!(est, obs, on=I)
        df = DataFrames.innerjoin(est, obs, on=I, makeunique=true)
        r = [metric(df[!, e], df[!, o]) for (e, o) in zip(T, T1)]
    end
    config(X) = parameterzip(K, X)
    cost(X) = begin
        c = config(X)
        l = length(configs)
        R = Vector(undef, l)
        Threads.@threads for i in 1:l
            R[i] = residual(configure(configs[i], c))
        end
        A = eachrow(hcat(R...)) .|> Iterators.flatten .|> collect |> deunitfy
        e = eachrow(hcat(A...)) |> sum
        # BlackBoxOptim expects Float64, not even Int
        e = Float64.(e)
        multi ? Tuple(e) : e[1]
    end
    #FIXME: input parameters units are ignored without conversion
    range = map(p -> Float64.(Tuple(deunitfy(p))), parametervalues(P))
    method = if multi
        agg = isnothing(weight) ? mean : let w = StatsBase.weights(weight); f -> mean(f, w) end
        (Method=:borg_moea, FitnessScheme=BlackBoxOptim.ParetoFitnessScheme{n}(aggregator=agg))
    else
        ()
    end
    optim_default = (;
        MaxSteps=5000,
        TraceInterval=10,
        RandomizeRngSeed=false,
    )
    #HACK: always initialize random seed first on our end regardless of RandomizeRngSeed option
    # https://github.com/robertfeldt/BlackBoxOptim.jl/issues/158
    Random.seed!(0)
    r = BlackBoxOptim.bboptimize(cost;
        SearchRange=range,
        method...,
        optim_default...,
        optim...
    )
    if multi && pareto
        pf = BlackBoxOptim.pareto_frontier(r)
        OrderedDict(BlackBoxOptim.fitness.(pf) .=> config.(BlackBoxOptim.params.(pf)))
    else
        config(BlackBoxOptim.best_candidate(r))
    end
end

export calibrate
