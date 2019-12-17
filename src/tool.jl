parsesimulatekey(p::Pair) = p
parsesimulatekey(a::Symbol) = (a => a)
parsesimulatekey(a::String) = (Symbol(split(a, ".")[end]) => a)
parsesimulate(s::System, index, columns) = begin
    C = isempty(columns) ? fieldnamesunique(s) : columns
    N = [index, C...]
    (; parsesimulatekey.(N)...)
end

import DataFrames: DataFrame
createresult(s::System, base, ic) = begin
    R = []
    K = []
    b = s[base]
    for (c, k) in pairs(ic)
        v = value(b[k])
        if v isa Union{Number,Symbol,String}
            push!(R, c => v)
            push!(K, k)
        end
    end
    (DataFrame(; R...), K)
end

using ProgressMeter: @showprogress, ProgressUnknown, ProgressMeter
updateresult!(s::System, n, df, keys; terminate=nothing, verbose=true) = begin
    update() = begin
        update!(s)
        r = Tuple(value(s[k]) for k in keys)
        push!(df, r)
    end
    #TODO: combine @showprogress (Progress) and ProgressUnknown
    if isnothing(terminate)
        t = verbose ? 1 : Inf
        @showprogress t for i in 1:n
            update()
        end
    else
        p = ProgressUnknown("Iterations:")
        while !s[terminate]'
            update()
            ProgressMeter.next!(p)
        end
        ProgressMeter.finish!(p)
    end
end

[
    [nothing, ["context.clock.tick"], ["a", "b", "c"]],
    ["leaves[*]", ["context.clock.tick", "rank"], ["a", "b", "c"]],
]

simulate!(s::System, n=1; base=nothing, index="context.clock.tick", columns=(), terminate=nothing, verbose=true, nounit=false) = begin
    T = parsesimulate(s, index, columns)
    df, K = createresult(s, base, T)
    updateresult!(s, n, df, K; terminate=terminate, verbose=verbose)
    nounit ? deunitfy.(df) : df
end

simulate(S::Type{<:System}, n=1; config=(), options=(), kwargs...) = begin
    s = instance(S, config=config; options...)
    simulate!(s, n; kwargs...)
end

import DataStructures: OrderedDict, DefaultDict
import BlackBoxOptim: bboptimize, best_candidate
calibrate(S::Type{<:System}, obs, n=1; index="context.clock.tick", column, config=(), parameters) = begin
    P = OrderedDict(parameters)
    K = [Symbol.(split(n, ".")) for n in keys(P)]
    makeconfig(X) = begin
        d = DefaultDict(Dict)
        for (k, v) in zip(K, X)
            d[k[1]][k[2]] = v
        end
        configure(config, d)
    end
    i = parsesimulatekey(index)[1]
    k = parsesimulatekey(column)[1]
    k1 = Symbol(k, :_1)
    cost(X) = begin
        est = simulate(S, n; config=makeconfig(X), index=index, columns=(column,), verbose=false)
        df = join(est, obs, on=i, makeunique=true)
        R = df[!, k] - df[!, k1]
        sum(R.^2) |> deunitfy
    end
    #FIXME: input parameters units are ignored without conversion
    range = map(p -> Float64.(Tuple(deunitfy(p))), values(P))
    r = bboptimize(cost; SearchRange=range)
    best_candidate(r) |> makeconfig
end

export simulate, simulate!, calibrate
