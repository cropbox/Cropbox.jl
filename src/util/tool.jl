import DataStructures: OrderedDict
import DataFrames: DataFrame
import Dates: AbstractDateTime

struct Simulation
    base::Union{String,Symbol,Nothing}
    index::OrderedDict
    target::OrderedDict
    result::DataFrame
end

simulation(s::System; base=nothing, index="context.clock.tick", target=nothing) = begin
    I = parsesimulation(index)
    T = parsesimulation(isnothing(target) ? fieldnamesunique(s[base]) : target)
    Simulation(base, I, T, DataFrame())
end

parsesimulationkey(p::Pair) = p
parsesimulationkey(a::Symbol) = (a => a)
parsesimulationkey(a::String) = (Symbol(split(a, ".")[end]) => a)
parsesimulation(a::Vector) = OrderedDict(parsesimulationkey.(a))
parsesimulation(a::Tuple) = parsesimulation(collect(a))
parsesimulation(a) = parsesimulation([a])

extract(s::System, m::Simulation) = extract(s[m.base], m.index, m.target)
extract(s::System, index, target) = begin
    d = merge(index, target)
    K = collect(keys(d))
    #HACK: prevent type promotion with NoUnits
    V = Any[value(s[k]) for k in values(d)]
    od = OrderedDict(K .=> V)
    filter!(p -> extractable(s, p), od)
    DataFrame(od)
end
extract(b::Bundle{S}, index, target) where {S<:System} = begin
    vcat([extract(s, index, target) for s in collect(b)]...)
end
extractable(s::System, p) = begin
    # only pick up variables of simple types by default
    p[2] isa Union{Number,Symbol,AbstractString,AbstractDateTime}
end

update!(m::Simulation, s::System) = append!(m.result, extract(s, m))

format(m::Simulation; nounit=false, long=false) = begin
    r = m.result
    if nounit
        r = deunitfy.(r)
    end
    if long
        i = collect(keys(m.index))
        t = setdiff(names(r), i)
        r = DataFrames.stack(r, t, i)
    end
    r
end

using ProgressMeter: Progress, ProgressUnknown, ProgressMeter
progress!(s::System, M::Vector{Simulation}; stop=nothing, skipfirst=false, callback=nothing, verbose=true, kwargs...) = begin
    isnothing(stop) && (stop = 1)
    isnothing(callback) && (callback = s -> true)
    n = if stop isa Number
        stop
    else
        v = s[stop]'
        if v isa Bool
            nothing
        elseif v isa Number
            v
        else
            error("unrecognized stop condition: $stop")
        end
    end
    check = if n isa Number
        dt = verbose ? 1 : Inf
        p = Progress(n, dt=dt)
        () -> p.counter < p.n
    else
        p = ProgressUnknown("Iterations:")
        () -> !s[stop]'
    end
    !skipfirst && update!.(M, s)
    while check()
        update!(s)
        callback(s) != false && update!.(M, s)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
    format.(M; kwargs...)
end

simulate!(s::System; base=nothing, index="context.clock.tick", target=nothing, kwargs...) = begin
    simulate!(s, [(base=base, index=index, target=target)]; kwargs...) |> only
end
simulate!(s::System, layout; kwargs...) = begin
    M = [simulation(s; l...) for l in layout]
    progress!(s, M; kwargs...)
end

simulate(S::Type{<:System}; base=nothing, index="context.clock.tick", target=nothing, kwargs...) = begin
    simulate(S, [(base=base, index=index, target=target)]; kwargs...) |> only
end
simulate(S::Type{<:System}, layout; config=(), options=(), configs=[], kwargs...) = begin
    if isempty(configs)
        s = instance(S, config=config; options...)
        simulate!(s, layout; kwargs...)
    else
        @assert isempty(config) && isempty(options)
        simulate(S, layout, configs; kwargs...)
    end
end
simulate(S::Type{<:System}, layout, configs; kwargs...) = begin
    R = [simulate(S, layout; config=c, kwargs...) for c in configs]
    [vcat(r...) for r in eachrow(hcat(R...))]
end

import BlackBoxOptim: bboptimize, best_candidate, ParetoFitnessScheme
calibrate(S::Type{<:System}, obs; config=(), kwargs...) = calibrate(S, obs, [config]; kwargs...)
calibrate(S::Type{<:System}, obs, configs; index="context.clock.tick", target, parameters, returnconfig=true, optim=(), kwargs...) = begin
    P = configure(parameters)
    K = parameterkeys(P)
    I = parsesimulation(index) |> keys |> collect
    T = parsesimulation(target) |> keys |> collect
    n = length(T)
    NT = DataFrames.make_unique([names(obs)..., T...], makeunique=true)
    T1 = NT[end-n+1:end]
    residual(c) = begin
        est = simulate(S; config=c, index=index, target=target, verbose=false, kwargs...)
        df = join(est, obs, on=I, makeunique=true)
        r = [df[!, e] - df[!, o] for (e, o) in zip(T, T1)]
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
        e = sum(eachrow(hcat(A...) .^2))
        n > 1 ? Tuple(e) : e[1]
    end
    #FIXME: input parameters units are ignored without conversion
    range = map(p -> Float64.(Tuple(deunitfy(p))), parametervalues(P))
    method = n > 1 ? (Method=:borg_moea, FitnessScheme=ParetoFitnessScheme{n}()) : ()
    r = bboptimize(cost;
        SearchRange=range,
        method...,
        optim...
    )
    returnconfig ? best_candidate(r) |> config : r
end

export simulate, simulate!, calibrate
