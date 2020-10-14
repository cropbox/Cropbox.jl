import DataFrames
using StatsBase: StatsBase, mean

#TODO: share code with calibrate()
validate(S::Type{<:System}, obs; config=(), configs=[], kwargs...) = begin
    if isempty(configs)
        validate(S, obs, [config]; kwargs...)
    elseif isempty(config)
        validate(S, obs, configs; kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
validate(S::Type{<:System}, obs, configs; index=nothing, target, metric=nothing, weight=nothing, normalize_index=false, kwargs...) = begin
    I = parsesimulation(index) |> keys |> collect
    T = parsesimulation(target) |> keys |> collect
    n = length(T)
    multi = n > 1
    isnothing(metric) && (metric = :rmse)
    metric = if metric == :rmse
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
        metric
    end
    IC = [t for t in zip(getproperty.(Ref(obs), I)...)]
    IV = parsesimulation(index) |> values |> Tuple
    snap(s) = getproperty.(s, IV) .|> value in IC
    NT = DataFrames.make_unique([propertynames(obs)..., T...], makeunique=true)
    T1 = NT[end-n+1:end]
    #HACK: handle index columns with non-identical, but compatible units
    # https://github.com/JuliaData/DataFrames.jl/issues/2486
    normalize(dfs...) = begin
        for i in I
            cols = getindex.(dfs, !, i)
            elts = eltype.(cols)
            t = promote_type(elts...)
            for (d, c, e) in zip(dfs, cols, elts)
                e != t && setindex!(d, convert.(t, c), !, i)
            end
        end
    end
    residual(c) = begin
        est = simulate(S; config=c, index, target, snap, verbose=false, kwargs...)
        isempty(est) && return repeat([Inf], n)
        normalize_index && normalize(est, obs)
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

export validate
