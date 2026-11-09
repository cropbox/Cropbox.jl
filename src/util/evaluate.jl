import DataFrames
using StatsBase: StatsBase, mean

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
    n = length(dfs)
    is(i::Symbol) = repeat([i], n)
    is(i) = collect(i)
    for i in on
        cols = getindex.(dfs, !, is(i))
        elts = eltype.(cols)
        t = promote_type(elts...)
        for (d, c, e) in zip(dfs, cols, elts)
            e != t && setindex!(d, convert.(t, c), !, i)
        end
    end
end

aligndata(obs, est, y; index, allowempty = false, rows = nothing) = begin
    isempty(est) && throw(ArgumentError("no matching indices between observations and estimates"))
    I = parseindex(index, obs)
    T = parsetarget(y, obs)
    K = Symbol.(keys(I))
    O, E = [gensym(:obs) for _ in T], [gensym(:est) for _ in T]
    # copy only the needed columns, keeping target names distinct across tables
    obs = DataFrames.select(obs, K, (collect(keys(T)) .=> O)...)
    est = DataFrames.select(est, (collect(values(I)) .=> K)..., (collect(values(T)) .=> E)...)
    row = gensym(:row)
    isnothing(rows) || (obs[!, row] = 1:nrow(obs))
    normalize!(obs, est; on = K)
    df = DataFrames.innerjoin(obs, est; on = K)
    isempty(df) && !allowempty && throw(ArgumentError("no matching indices between observations and estimates"))
    isnothing(rows) || append!(rows, df[!, row])
    getproperty.(Ref(df), O), getproperty.(Ref(df), E)
end

filterobservations(obs, target) = begin
    obs = DataFrames.dropmissing(obs, target)
    isempty(obs) && throw(ArgumentError("no complete observations for the requested targets"))
    obs
end

warnmatching(obs, rows; context = "evaluation") = begin
    matched, total = length(unique(rows)), nrow(obs)
    0 < matched < total || return false
    @warn "partial observation matching in $context: $matched of $total complete observations matched; check index, stop, and snap"
    true
end

indexequal(a, b) = isequal(a, b)
indexequal(a::Number, b::Number) = isequal(promote(a, b)...)
indexequal(a::Tuple, b::Tuple) = length(a) == length(b) && all(indexequal(x, y) for (x, y) in zip(a, b))
indexcontains(x, xs) = any(y -> indexequal(x, y), xs)

"""
    evaluate(S, obs; <keyword arguments>) -> Number | Tuple

Compare output of simulation results for the given system `S` and observation data `obs` with a choice of evaluation metric.

# Arguments
- `S::Type{<:System}`: type of system to be evaluated.
- `obs::DataFrame`: observation data to be used for evaluation.

# Keyword Arguments
## Configuration
- `config=()`: a single configuration for the system (can't be used with `configs`).
- `configs=[]`: multiple configurations for the system (can't be used with `config`).

## Layout
- `index=nothing`: variables to construct index columns of the output; default falls back to `context.clock.time`.
- `target`: variables to construct non-index columns of the output.

## Evaluation
- `metric=nothing`: evaluation metric (`:rmse`, `:nrmse`, `:mae`, `:mape`, `:ef`, `:dr`); default is RMSE.
- `warn=true`: warn when only part of the complete observations match.

Remaining keyword arguments are passed down to `simulate` with regard to running system `S`.
Rows missing any requested observation target are omitted. An `ArgumentError`
is raised if no complete observations or no matching output remain.
Partial matches warn with the number of matched and complete observations.

See also: [`simulate`](@ref), [`calibrate`](@ref), [`@config`](@ref)

# Examples
```julia-repl
julia> @system S(Controller) begin
           a => 19 ~ preserve(u"m/hr", parameter)
           b(a) ~ accumulate(u"m")
       end;

julia> obs = DataFrame(time=10u"hr", b=200u"m");

julia> configs = @config !(:S => :a => [19, 21]);

julia> evaluate(S, obs; configs, target=:b, stop=10u"hr")
10.0 m
```
"""
evaluate(S::Type{<:System}, obs; config=(), configs=[], kwargs...) = begin
    if isempty(configs)
        evaluate(S, obs, [config]; kwargs...)
    elseif isempty(config)
        evaluate(S, obs, configs; kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
evaluate(S::Type{<:System}, obs, configs; index=nothing, target, metric=nothing, warn = true, kwargs...) = begin
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
    cost() = begin
        l = length(configs)
        R = Vector(undef, l)
        rows = warn ? Int[] : nothing
        Threads.@threads for i in 1:l
            R[i] = simulate(S; config = configs[i], index, target, snap, verbose = false, kwargs...)
        end
        R = map(R) do est
            O, E = aligndata(obs, est, T; index = I, rows)
            collect(zip(E, O))
        end
        e = map(getindex.(R, i) for i in 1:n) do r
            metric(vcat(first.(r)...), vcat(last.(r)...))
        end
        warn && warnmatching(obs, rows)
        multi ? Tuple(e) : only(e)
    end
    cost()
end

"""
    evaluate(obs, est; <keyword arguments>) -> Number | Tuple

Compare observation data `obs` and estimation data `est` with a choice of evaluation metric.

# Arguments
- `obs::AbstractDataFrame`: observation data to be used for evaluation.
- `est::AbstractDataFrame`: estimated data from simulation.

# Keyword Arguments
## Layout
- `index=nothing`: index columns, defaulting to `:time`; pairs map observation columns to estimate columns.
- `target`: variables referring to non-index columns of the output.

## Evaluation
- `metric=nothing`: evaluation metric (`:rmse`, `:nrmse`, `:mae`, `:mape`, `:ef`, `:dr`); default is RMSE.
- `warn=true`: warn when only part of the complete observations match.

See also: [`evaluate`](@ref)

Neither input table is modified. Rows missing any requested target are omitted.
An `ArgumentError` is raised if no complete matching rows remain.
Partial matches warn with the number of matched and complete observations.

# Examples
```julia-repl
julia> obs = DataFrame(time = [1, 2, 3]u"hr", b = [10, 20, 30]u"g");

julia> est = DataFrame(time = [1, 2, 3]u"hr", b = [10, 20, 30]u"g", c = [11, 19, 31]u"g");

julia> evaluate(obs, est; index = :time, target = :b)
0.0 g

julia> evaluate(obs, est; index = :time, target = :b => :c)
1.0 g
```
"""
evaluate(obs::AbstractDataFrame, est::AbstractDataFrame; index = nothing, target, metric = nothing, warn = true, kwargs...) = begin
    isnothing(index) && (index = :time)
    obs = filterobservations(obs, collect(keys(parsetarget(target, obs))))
    rows = warn ? Int[] : nothing
    Xs, Ys = aligndata(obs, est, target; index, rows)
    isnothing(metric) && (metric = :rmse)
    metric = metricfunc(metric)
    keep = map((v...) -> all(!ismissing, v), Xs..., Ys...)
    any(keep) || throw(ArgumentError("no complete matching rows for the requested targets"))
    e = [metric(Y[keep], X[keep]) for (X, Y) in zip(Xs, Ys)]
    warn && warnmatching(obs, rows[keep])
    length(e) == 1 ? only(e) : Tuple(e)
end

export evaluate
