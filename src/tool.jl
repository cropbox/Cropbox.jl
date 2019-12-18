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
    b = s[base]
    I = parsesimulation(index)
    T = if isempty(target)
        #HACK: only pick up variables of simple types by default
        filter(p -> begin
            k = p.second; value(b[k]) isa Union{Number,Symbol,String}
        end, parsesimulation(fieldnamesunique(s)))
    else
        parsesimulation(target)
    end
    result = extract(b, I, T)
    Simulation(s, base, I, T, result)
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
    DataFrame(OrderedDict(zip(K, V)))
end

format(m::Simulation; nounit=false, long=false) = begin
    r = m.result
    r = nounit ? deunitfy.(r) : r
    r = long ? stack(r, collect(keys(m.target)), collect(keys(m.index))) : r
end

using ProgressMeter: Progress, ProgressUnknown, ProgressMeter
update!(m::Simulation, n; terminate=nothing, verbose=true, kwargs...) = begin
    s = m.system
    check = if isnothing(terminate)
        dt = verbose ? 1 : Inf
        p = Progress(n, dt=dt)
        () -> p.counter < p.n
    else
        p = ProgressUnknown("Iterations:")
        () -> !s[terminate]'
    end
    while check()
        update!(s)
        append!(m.result, extract(m))
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
    update!(m, n; kwargs...)
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
