using DataStructures: OrderedDict
using DataFrames: DataFrame
using Dates: AbstractTime

struct Simulation
    base::Union{String,Symbol,Nothing}
    index::OrderedDict{Symbol,Any}
    target::OrderedDict{Symbol,Any}
    mapping::OrderedDict{Symbol,Any}
    meta::OrderedDict{Symbol,Any}
    result::DataFrame
end

@nospecialize

simulation(s::System; config=(), base=nothing, index=nothing, target=nothing, meta=nothing) = begin
    sb = s[base]
    I = parsesimulation(index)
    T = parsesimulation(isnothing(target) ? fieldnamesunique(s[base]) : target)
    #HACK: ignore unavailable properties (i.e. handle default :tick in target)
    I = filtersimulationdict(I, sb)
    T = filtersimulationdict(T, sb)
    IT = merge(I, T)
    M = parsemeta(meta, s.context.config)
    Simulation(base, I, T, IT, M, DataFrame())
end

parsesimulationkey(p::Pair) = [p]
parsesimulationkey(a::Symbol) = [a => a]
parsesimulationkey(a::String) = [Symbol(split(a, ".")[end]) => a]
parsesimulationkey(a::Vector) = parsesimulationkey.(a) |> Iterators.flatten |> collect
parsesimulation(a::Vector) = OrderedDict(parsesimulationkey.(a) |> Iterators.flatten)
parsesimulation(a::Tuple) = parsesimulation(collect(a))
parsesimulation(::Tuple{}) = parsesimulation([])
parsesimulation(a) = parsesimulation([a])
parsesimulation(::Nothing) = parsesimulation("context.clock.tick")

filtersimulationdict(m::OrderedDict, s::System) = filter(m) do (k, v); hasproperty(s, v) end

extract(s::System, m::Simulation) = extract(s[m.base], m.mapping)
extract(s::System, m::OrderedDict{Symbol,Any}) = begin
    K = keys(m)
    V = (value(s[k]) for k in values(m))
    #HACK: Any -- prevent type promotion with NoUnits
    d = OrderedDict{Symbol,Any}(zip(K, V))
    filter!(p -> extractable(s, p), d)
    [d]
end
extract(b::Bundle{S}, m::OrderedDict{Symbol,Any}) where {S<:System} = begin
    [extract(s, m) for s in collect(b)]
end
extractable(s::System, p) = begin
    # only pick up variables of simple types by default
    p[2] isa Union{Number,Symbol,AbstractString,AbstractTime}
end

parsemetadata(p::Pair, c) = p
parsemetadata(a::Symbol, c) = c[a]
parsemeta(a::Vector, c) = merge(parsemeta(nothing, c), OrderedDict.(parsemetadata.(a, Ref(c)))...)
parsemeta(a::Tuple, c) = parsemeta(collect(a), c)
parsemeta(a, c) = parsemeta([a], c)
parsemeta(::Nothing, c) = OrderedDict()

update!(m::Simulation, s::System, snatch!) = begin
    D = extract(s, m)
    snatch!(D, s)
    append!(m.result, D)
end

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

using ProgressMeter: Progress, ProgressUnknown, ProgressMeter
const barglyphs = ProgressMeter.BarGlyphs("[=> ]")
progress!(s::System, M::Vector{Simulation}; stop=nothing, snap=nothing, snatch=nothing, callback=nothing, verbose=true, kwargs...) = begin
    probe(a::Union{Symbol,String}) = s -> s[a]'
    probe(a::Function) = s -> a(s)
    probe(a) = s -> a

    stopprobe(::Nothing) = probe(0)
    stopprobe(a) = probe(a)

    snapprobe(::Nothing) = probe(true)
    snapprobe(a::Quantity) = s -> let c = s.context.clock; (c.tick' - c.init') % a |> iszero end
    snapprobe(a) = probe(a)

    stop = stopprobe(stop)
    snap = snapprobe(snap)
    snatch = isnothing(snatch) ? (D, s) -> nothing : snatch
    callback = isnothing(callback) ? (s, m) -> nothing : callback

    count(v::Number) = v
    count(v::Quantity) = ceil(Int, v / s.context.clock.step')
    count(v::Bool) = nothing
    count(v) = error("unrecognized stop condition: $v")
    n = count(stop(s))

    dt = verbose ? 1 : Inf
    if n isa Number
        p = Progress(n; dt, barglyphs)
        check = s -> p.counter < p.n
    else
        p = ProgressUnknown(; dt, desc="Iterations:")
        check = s -> !stop(s)
    end

    snap(s) && update!.(M, s, snatch)
    while check(s)
        update!(s)
        snap(s) && for m in M
            update!(m, s, snatch)
            callback(s, m)
        end
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
    format!.(M; kwargs...)
end

simulate!(s::System; base=nothing, index=nothing, target=nothing, meta=nothing, kwargs...) = begin
    simulate!(s, [(; base, index, target, meta)]; kwargs...) |> only
end
simulate!(s::System, layout::Vector; kwargs...) = begin
    M = [simulation(s; l...) for l in layout]
    progress!(s, M; kwargs...)
end
simulate!(f::Function, s::System, args...; kwargs...) = simulate!(s, args...; snatch=f, kwargs...)

simulate(; system, kw...) = simulate(system; kw...)
simulate(S::Type{<:System}; base=nothing, index=nothing, target=nothing, meta=nothing, kwargs...) = begin
    simulate(S, [(; base, index, target, meta)]; kwargs...) |> only
end
simulate(S::Type{<:System}, layout::Vector; config=(), configs=[], options=(), seed=nothing, kwargs...) = begin
    if isempty(configs)
        s = instance(S; config, options, seed)
        simulate!(s, layout; kwargs...)
    elseif isempty(config)
        simulate(S, layout, configs; options, seed, kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
simulate(S::Type{<:System}, layout::Vector, configs::Vector; verbose=true, kwargs...) = begin
    n = length(configs)
    R = Vector(undef, n)
    dt = verbose ? 1 : Inf
    p = Progress(n; dt, barglyphs)
    Threads.@threads for i in 1:n
        R[i] = simulate(S, layout; config=configs[i], verbose=false, kwargs...)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
    [vcat(r...) for r in eachrow(hcat(R...))]
end
simulate(f::Function, S::Type{<:System}, args...; kwargs...) = simulate(S, args...; snatch=f, kwargs...)

@specialize

export simulate, simulate!
