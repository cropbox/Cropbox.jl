import DataFrames
using StatsBase: StatsBase, mean

#TODO: share code with calibrate()
evaluate(S::Type{<:System}, obs; config=(), configs=[], kwargs...) = begin
    if isempty(configs)
        evaluate(S, obs, [config]; kwargs...)
    elseif isempty(config)
        evaluate(S, obs, configs; kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
evaluate(S::Type{<:System}, obs, configs; index=nothing, target, metric=nothing, weight=nothing, kwargs...) = begin
    #HACK: use copy due to normalize!
    obs = copy(obs)
    I = parsesimulation(index) |> keys |> collect
    T = parsesimulation(target) |> keys |> collect
    n = length(T)
    multi = n > 1
    isnothing(metric) && (metric = :rmse)
    metric = metricfunc(metric)
    IC = [t for t in zip(getproperty.(Ref(obs), I)...)]
    IV = parsesimulation(index) |> values |> Tuple
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
    cost() = begin
        l = length(configs)
        R = Vector(undef, l)
        Threads.@threads for i in 1:l
            R[i] = residual(configs[i])
        end
        A = eachrow(hcat(R...)) .|> Iterators.flatten .|> collect #|> deunitfy
        e = eachrow(hcat(A...)) #|> sum
        e = sum(e)
        multi ? Tuple(e) : e[1]
    end
    agg = if multi
        if isnothing(weight)
            mean
        else
            let w = StatsBase.weights(weight); f -> mean(f, w) end
        end
    else
        identity
    end
    cost() |> agg
end

validate(S::Type{<:System}, args...; kwargs...) = begin
    @warn "use evaluate() instead"
    evaluate(S, args...; kwargs...)
end

export evaluate, validate
