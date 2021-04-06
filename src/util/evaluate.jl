import DataFrames

#TODO: share code with calibrate()
"""
    evaluate(S, obs; <keyword arguments>) -> Number | Tuple

Compare output of simulation results for the given system `S` and observation data `obs` with a choice of evaluation metric.

# Arguments
- `S::Type{<:System}`: type of system to be evaluated.
- `obs::DataFrame`: observatioan data to be used for evaluation.

# Keyword Arguments
## Configuration
- `config=()`: a single configuration for the system (can't be used with `configs`).
- `configs=[]`: multiple configurations for the system (can't be used with `config`).

## Layout
- `index=nothing`: variables to construct index columns of the output; default falls back to `context.clock.time`.
- `target`: variables to construct non-index columns of the output.

## Evaluation
- `metric=nothing`: evaluation metric (`:rmse`, `:nrmse`, `:mae`, `:mape`, `:ef`, `:dr`); default is RMSE.

Remaining keyword arguments are passed down to `simulate` with regard to running system `S`.

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
evaluate(S::Type{<:System}, obs, configs; index=nothing, target, metric=nothing, kwargs...) = begin
    #HACK: use copy due to normalize!
    obs = copy(obs)
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
        r = [(df[!, e], df[!, o]) for (e, o) in zip(T, T1)]
    end
    cost() = begin
        l = length(configs)
        R = Vector(undef, l)
        Threads.@threads for i in 1:l
            R[i] = residual(configs[i])
        end
        e = map(getindex.(R, i) for i in 1:n) do r
            metric(vcat(first.(r)...), vcat(last.(r)...))
        end
        multi ? Tuple(e) : only(e)
    end
    cost()
end

export evaluate
