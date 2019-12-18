import DataStructures: OrderedDict
import DataFrames: DataFrame, stack

struct Simulation{S<:System}
    system::S
    base::Union{String,Nothing}
    index::OrderedDict
    target::OrderedDict
    result::DataFrame
end

Simulation(s::System, base, index, target) = begin
    I = parsesimulation(index)
    T = parsesimulation(isempty(target) ? fieldnamesunique(s[base]) : target)
    Simulation(s, base, I, T, DataFrame())
end

parsesimulationkey(p::Pair) = p
parsesimulationkey(a::Symbol) = (a => a)
parsesimulationkey(a::String) = (Symbol(split(a, ".")[end]) => a)
parsesimulation(a::Vector) = OrderedDict(parsesimulationkey.(a))
parsesimulation(a::Tuple) = parsesimulation(collect(a))
parsesimulation(a) = parsesimulation([a])

extract(m::Simulation) = extract(m.system[m.base], m.index, m.target)
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

update!(m::Simulation) = append!(m.result, extract(m))

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
progress!(m::Simulation, n; terminate=nothing, verbose=true, kwargs...) = begin
    s = m.system
    check = if isnothing(terminate)
        dt = verbose ? 1 : Inf
        p = Progress(n, dt=dt)
        () -> p.counter < p.n
    else
        p = ProgressUnknown("Iterations:")
        () -> !s[terminate]'
    end
    update!(m)
    while check()
        update!(s)
        update!(m)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
    format(m; kwargs...)
end

[
    [nothing, ["context.clock.tick"], ["a", "b", "c"]],
    ["leaves[*]", ["context.clock.tick", "rank"], ["a", "b", "c"]],
]

simulate!(s::System, n=1; base=nothing, index="context.clock.tick", columns=(), kwargs...) = begin
    m = Simulation(s, base, index, columns)
    progress!(m, n; kwargs...)
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
    i = parsesimulationkey(index).first
    k = parsesimulationkey(column).first
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
