using DataStructures: OrderedDict
using DataFrames: DataFrame
using StatsBase: StatsBase, mean
import Random
import BlackBoxOptim

@nospecialize

calibrate(S::Type{<:System}, obs; config=(), configs=[], kwargs...) = begin
    if isempty(configs)
        calibrate(S, obs, [config]; kwargs...)
    elseif isempty(config)
        calibrate(S, obs, configs; kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
calibrate(S::Type{<:System}, obs, configs; index=nothing, target, parameters, metric=nothing, weight=nothing, pareto=false, optim=(), kwargs...) = begin
    P = configure(parameters)
    K = parameterkeys(P)
    I = parsesimulation(index) |> keys |> collect
    T = parsesimulation(target) |> keys |> collect
    n = length(T)
    multi = n > 1
    isnothing(metric) && (metric = :rmse)
    if metric == :rmse
        metric = (E, O) -> √(mean((E - O).^2))
    elseif metric == :prmse
        metric = (E, O) -> √(mean(((E - O) ./ O).^2))
    end
    IC = [t for t in zip(getproperty.(Ref(obs), I)...)]
    IV = parsesimulation(index) |> values |> Tuple
    snap(s) = getproperty.(s, IV) .|> value in IC
    NT = DataFrames.make_unique([propertynames(obs)..., T...], makeunique=true)
    T1 = NT[end-n+1:end]
    residual(c) = begin
        est = simulate(S; config=c, index, target, snap, verbose=false, kwargs...)
        isempty(est) && return [Inf]
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
    #HACK: always initialize random seed first on our end regardless of RandomizeRngSeed option
    # https://github.com/robertfeldt/BlackBoxOptim.jl/issues/158
    Random.seed!(0)
    r = BlackBoxOptim.bboptimize(cost;
        SearchRange=range,
        method...,
        optim...
    )
    if multi && pareto
        pf = BlackBoxOptim.pareto_frontier(r)
        OrderedDict(BlackBoxOptim.fitness.(pf) .=> config.(BlackBoxOptim.params.(pf)))
    else
        config(BlackBoxOptim.best_candidate(r))
    end
end

@specialize

export calibrate
