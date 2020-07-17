import DataStructures: OrderedDict
import DataFrames: DataFrame
import Dates: AbstractDateTime

struct Simulation
    base::Union{String,Symbol,Nothing}
    index::OrderedDict
    target::OrderedDict
    meta::OrderedDict{Symbol,Any}
    result::DataFrame
end

simulation(s::System; config=(), base=nothing, index=nothing, target=nothing, meta=nothing) = begin
    I = parsesimulation(index)
    T = parsesimulation(isnothing(target) ? fieldnamesunique(s[base]) : target)
    M = parsemeta(meta, s.context.config)
    Simulation(base, I, T, M, DataFrame())
end

parsesimulationkey(p::Pair) = p
parsesimulationkey(a::Symbol) = (a => a)
parsesimulationkey(a::String) = (Symbol(split(a, ".")[end]) => a)
parsesimulation(a::Vector) = OrderedDict(parsesimulationkey.(a))
parsesimulation(a::Tuple) = parsesimulation(collect(a))
parsesimulation(a) = parsesimulation([a])
parsesimulation(::Nothing) = parsesimulation("context.clock.tick")

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

parsemetadata(p::Pair, c) = p
parsemetadata(a::Symbol, c) = c[a]
parsemeta(a::Vector, c) = merge(parsemeta(nothing, c), OrderedDict.(parsemetadata.(a, Ref(c)))...)
parsemeta(a::Tuple, c) = parsemeta(collect(a), c)
parsemeta(a, c) = parsemeta([a], c)
parsemeta(::Nothing, c) = OrderedDict()

update!(m::Simulation, s::System) = append!(m.result, extract(s, m))

format!(m::Simulation; nounit=false, long=false) = begin
    r = m.result
    for (k, v) in m.meta
        r[!, k] .= v 
    end
    if nounit
        r = deunitfy.(r)
    end
    if long
        i = collect(keys(m.index))
        t = setdiff(propertynames(r), i)
        r = DataFrames.stack(r, t, i)
    end
    r
end

import ProgressMeter: Progress, ProgressUnknown, ProgressMeter
const barglyphs = ProgressMeter.BarGlyphs("[=> ]")
progress!(s::System, M::Vector{Simulation}; stop=nothing, skipfirst=false, filter=nothing, callback=nothing, verbose=true, kwargs...) = begin
    isnothing(stop) && (stop = 1)
    isnothing(filter) && (filter = s -> true)
    isnothing(callback) && (callback = s -> nothing)
    n = if stop isa Number
        stop
    else
        v = stop isa Symbol || stop isa String ? s[stop]' : stop(s)
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
        p = Progress(n; dt=dt, barglyphs=barglyphs)
        () -> p.counter < p.n
    else
        p = ProgressUnknown("Iterations:")
        if stop isa Symbol || stop isa String
            () -> !s[stop]'
        else
            () -> !stop(s)
        end
    end
    !skipfirst && filter(s) && update!.(M, s)
    while check()
        update!(s)
        filter(s) && update!.(M, s)
        callback(s)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
    format!.(M; kwargs...)
end

simulate!(s::System; base=nothing, index=nothing, target=nothing, meta=nothing, kwargs...) = begin
    simulate!(s, [(base=base, index=index, target=target, meta=meta)]; kwargs...) |> only
end
simulate!(s::System, layout; kwargs...) = begin
    M = [simulation(s; l...) for l in layout]
    progress!(s, M; kwargs...)
end
simulate!(f::Function, s::System, args...; kwargs...) = simulate!(s, args...; callback=f, kwargs...)

simulate(S::Type{<:System}; base=nothing, index=nothing, target=nothing, meta=nothing, kwargs...) = begin
    simulate(S, [(base=base, index=index, target=target, meta=meta)]; kwargs...) |> only
end
simulate(S::Type{<:System}, layout; config=(), configs=[], options=(), seed=nothing, kwargs...) = begin
    if isempty(configs)
        s = instance(S; config=config, options=options, seed=seed)
        simulate!(s, layout; kwargs...)
    elseif isempty(config)
        simulate(S, layout, configs; options=options, kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
simulate(S::Type{<:System}, layout, configs; verbose=true, kwargs...) = begin
    n = length(configs)
    R = Vector(undef, n)
    dt = verbose ? 1 : Inf
    p = Progress(n; dt=dt, barglyphs=barglyphs)
    Threads.@threads for i in 1:n
        R[i] = simulate(S, layout; config=configs[i], verbose=false, kwargs...)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
    [vcat(r...) for r in eachrow(hcat(R...))]
end
simulate(f::Function, S::Type{<:System}, args...; kwargs...) = simulate(S, args...; callback=f, kwargs...)

export simulate, simulate!
