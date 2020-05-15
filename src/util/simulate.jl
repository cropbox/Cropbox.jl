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
progress!(s::System, M::Vector{Simulation}; stop=nothing, skipfirst=false, filter=nothing, callback=nothing, verbose=true, kwargs...) = begin
    isnothing(stop) && (stop = 1)
    isnothing(filter) && (filter = s -> true)
    isnothing(callback) && (callback = s -> nothing)
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
        filter(s) != false && update!.(M, s)
        callback(s)
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
simulate!(f::Function, s::System, args...; kwargs...) = simulate!(s, args...; callback=f, kwargs...)

simulate(S::Type{<:System}; base=nothing, index="context.clock.tick", target=nothing, kwargs...) = begin
    simulate(S, [(base=base, index=index, target=target)]; kwargs...) |> only
end
simulate(S::Type{<:System}, layout; config=(), configs=[], options=(), kwargs...) = begin
    if isempty(configs)
        s = instance(S; config=config, options...)
        simulate!(s, layout; kwargs...)
    elseif isempty(config)
        simulate(S, layout, configs; options=options, kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
simulate(S::Type{<:System}, layout, configs; kwargs...) = begin
    R = [simulate(S, layout; config=c, kwargs...) for c in configs]
    [vcat(r...) for r in eachrow(hcat(R...))]
end
simulate(f::Function, S::Type{<:System}, args...; kwargs...) = simulate(S, args...; callback=f, kwargs...)

export simulate, simulate!
