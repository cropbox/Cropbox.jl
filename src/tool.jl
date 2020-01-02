import DataStructures: OrderedDict
import DataFrames: DataFrame, stack

struct Simulation
    base::Union{String,Nothing}
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
    V = map(k -> value(s[k]), values(d))
    od = OrderedDict(zip(K, V))
    #HACK: only pick up variables of simple types by default
    filter!(p -> p.second isa Union{Number,Symbol,String}, od)
    DataFrame(od)
end
extract(b::Bundle{S}, index, target) where {S<:System} = begin
    vcat([extract(s, index, target) for s in collect(b)]...)
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
        r = stack(r, t, i)
    end
    r
end

using ProgressMeter: Progress, ProgressUnknown, ProgressMeter
progress!(s::System, M::Vector{Simulation}; n, terminate=nothing, verbose=true, kwargs...) = begin
    check = if isnothing(terminate)
        dt = verbose ? 1 : Inf
        p = Progress(n, dt=dt)
        () -> p.counter < p.n
    else
        p = ProgressUnknown("Iterations:")
        () -> !s[terminate]'
    end
    update!.(M, s)
    while check()
        update!(s)
        update!.(M, s)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
    format.(M; kwargs...)
end

simulate!(s::System; n=1, base=nothing, index="context.clock.tick", target=nothing, kwargs...) = begin
    simulate!(s, [(base=base, index=index, target=target)]; n=n, kwargs...)[1]
end
simulate!(s::System, layout; n=1, kwargs...) = begin
    M = [simulation(s; l...) for l in layout]
    progress!(s, M; n=n, kwargs...)
end

simulate(S::Type{<:System}; n=1, base=nothing, index="context.clock.tick", target=nothing, kwargs...) = begin
    simulate(S, [(base=base, index=index, target=target)]; n=n, kwargs...)[1]
end
simulate(S::Type{<:System}, layout; n=1, config=(), options=(), kwargs...) = begin
    s = instance(S, config=config; options...)
    simulate!(s, layout; n=n, kwargs...)
end
simulate(S::Type{<:System}, layout, configs; kwargs...) = begin
    R = [simulate(S, layout; config=c, kwargs...) for c in configs]
    [vcat(r...) for r in eachrow(hcat(R...))]
end

import DataStructures: OrderedDict, DefaultDict
import BlackBoxOptim: bboptimize, best_candidate
calibrate(S::Type{<:System}, obs; config=(), kwargs...) = calibrate(S, obs, [config]; kwargs...)
calibrate(S::Type{<:System}, obs, configs; n=1, index="context.clock.tick", target, parameters) = begin
    P = OrderedDict(parameters)
    K = [Symbol.(split(n, ".")) for n in keys(P)]
    config(X) = begin
        d = DefaultDict(Dict)
        for (k, v) in zip(K, X)
            d[k[1]][k[2]] = v
        end
        d
    end
    i = parsesimulation(index) |> keys |> collect
    k = parsesimulationkey(target).first
    k1 = Symbol(k, :_1)
    residual(c) = begin
        est = simulate(S; n=n, config=c, index=index, target=target, verbose=false)
        df = join(est, obs, on=i, makeunique=true)
        df[!, k] - df[!, k1]
    end
    cost(X) = begin
        c = config(X)
        l = length(configs)
        T = Vector(undef, l)
        Threads.@threads for i in 1:l
            T[i] = residual(configure(configs[i], c))
        end
        R = T |> Iterators.flatten
        sum(R.^2) |> deunitfy
    end
    #FIXME: input parameters units are ignored without conversion
    range = map(p -> Float64.(Tuple(deunitfy(p))), values(P))
    r = bboptimize(cost; SearchRange=range)
    best_candidate(r) |> config
end

export simulate, simulate!, calibrate
