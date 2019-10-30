parserunkey(p::Pair) = p
parserunkey(a::Symbol) = (a => a)
parserunkey(a::String) = (Symbol(split(a, ".")[end]) => a)
parserun(s::System, index, columns) = begin
    C = isempty(columns) ? fieldnamesunique(s) : columns
    N = [index, C...]
    (; parserunkey.(N)...)
end

import DataFrames: DataFrame
createresult(s::System, ic) = begin
    R = []
    K = []
    for (c, k) in pairs(ic)
        v = value(s[k])
        if typeof(v) <: Union{Number,Symbol,String}
            push!(R, c => v)
            push!(K, k)
        end
    end
    (DataFrame(; R...), K)
end

import ProgressMeter: @showprogress
updateresult!(s::System, n, df, keys; verbose=true) = begin
    t = verbose ? 1 : Inf
    @showprogress t for i in 1:n
        update!(s)
        r = Tuple(value(s[k]) for k in keys)
        push!(df, r)
    end
end

run!(s::System, n=1; index="context.clock.tick", columns=(), verbose=true, nounit=false) = begin
    T = parserun(s, index, columns)
    df, K = createresult(s, T)
    updateresult!(s, n, df, K; verbose=verbose)
    nounit ? deunitfy.(df) : df
end

run!(S::Type{<:System}, n=1; config=(), options=(), kwargs...) = begin
    s = instance(S, config=config, options...)
    run!(s, n; kwargs...)
end

import DataStructures: OrderedDict, DefaultDict
import BlackBoxOptim: bboptimize, best_candidate
fit!(S::Type{<:System}, obs, n=1; index="context.clock.tick", column, parameters) = begin
    P = OrderedDict(parameters)
    K = [Symbol.(split(n, ".")) for n in keys(P)]
    config(X) = begin
        d = DefaultDict(Dict)
        for (k, v) in zip(K, X)
            d[k[1]][k[2]] = v
        end
        configure(d)
    end
    i = parserunkey(index)[1]
    k = parserunkey(column)[1]
    k1 = Symbol(k, :_1)
    cost(X) = begin
        est = run!(S, n; config=config(X), index=index, columns=(column,), verbose=false)
        df = join(est, obs, on=i, makeunique=true)
        R = df[!, k] - df[!, k1]
        sum(R.^2)
    end
    range = collect(values(P))
    r = bboptimize(cost; SearchRange=range)
    best_candidate(r) |> config
end

export run!, fit!
