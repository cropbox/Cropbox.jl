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

simulation(s::System; config=(), base=nothing, index=nothing, target=nothing, meta=nothing) = begin
    sb = s[base]
    I = parseindex(index, sb)
    T = parsetarget(target, sb)
    #HACK: ignore unavailable properties (i.e. handle default :time in target)
    I = filtersimulationdict(I, sb)
    T = filtersimulationdict(T, sb)
    IT = merge(I, T)
    M = parsemeta(meta, s.context.config)
    Simulation(base, I, T, IT, M, DataFrame())
end

parsesimulationkey(p::Pair, s) = [p]
parsesimulationkey(a::Symbol, s) = [a => a]
parsesimulationkey(a::String, s) = [Symbol(a) => a]
parsesimulationkey(a::String, s::System) = begin
    A = split(a, '.')
    # support wildcard names (i.e. "s.*" expands to ["s.a", "s.b", ...])
    if A[end] == "*"
        a0 = join(A[1:end-1], '.')
        ss = s[a0]
        p(n) = let k = join(filter!(!isempty, [a0, string(n)]), '.')
            Symbol(k) => k
        end
        [p(n) for n in fieldnamesunique(ss)]
    else
        [Symbol(a) => a]
    end
end
parsesimulationkey(a::Vector, s) = parsesimulationkey.(a, Ref(s)) |> Iterators.flatten |> collect

parsesimulation(a::Vector, s) = OrderedDict(parsesimulationkey.(a, Ref(s)) |> Iterators.flatten)
parsesimulation(a::Tuple, s) = parsesimulation(collect(a), s)
parsesimulation(::Tuple{}, s) = parsesimulation([], s)
parsesimulation(a, s) = parsesimulation([a], s)

parseindex(::Nothing, s) = parsesimulation(:time => "context.clock.time", s)
parseindex(I, s) = parsesimulation(I, s)

parsetarget(::Nothing, s) = parsesimulation("*", s)
parsetarget(T, s) = parsesimulation(T, s)

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
    !isempty(D) && append!(m.result, D; cols=:union)
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
        r = sort!(r, i)
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
    snapprobe(a::Quantity) = s -> let c = s.context.clock; (c.time' - c.init') % a |> iszero end
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
    showspeed = true
    if n isa Number
        p = Progress(n; dt, barglyphs, showspeed)
        check = s -> p.counter < p.n
    else
        p = ProgressUnknown(; dt, desc="Iterations:", showspeed)
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

"""
    simulate!([f,] s[, layout]; <keyword arguments>) -> DataFrame

Run simulations with an existing instance of system `s`. The instance is altered by internal updates for running simulations.

See also: [`simulate`](@ref)
"""
simulate!(s::System; base=nothing, index=nothing, target=nothing, meta=nothing, kwargs...) = begin
    simulate!(s, [(; base, index, target, meta)]; kwargs...) |> only
end
simulate!(s::System, layout::Vector; kwargs...) = begin
    M = [simulation(s; l...) for l in layout]
    progress!(s, M; kwargs...)
end
simulate!(f::Function, s::System, args...; kwargs...) = simulate!(s, args...; snatch=f, kwargs...)

"""
    simulate([f,] S[, layout, [configs]]; <keyword arguments>) -> DataFrame

Run simulations by making instance of system `S` with given configuration to generate an output in the form of DataFrame. `layout` contains a list of variables to be saved in the output. A layout of single simulation can be specified in the layout arguments placed as keyword arguments. `configs` contains a list of configurations for each run of simulation. Total number of simulation runs equals to the size of `configs`. For a single configuration, `config` keyword argument may be preferred. Optional callback function `f` allows do-block syntax to specify `snatch` argument for finer control of output format.

See also: [`instance`](@ref), [`@config`](@ref)

# Arguments
- `S::Type{<:System}`: type of system to be simulated.
- `layout::Vector`: list of output layout definition in a named tuple `(; base, index, target, meta)`.
- `configs::Vector`: list of configurations for defining multiple runs of simluations.

# Keyword Arguments
## Layout
- `base=nothing`: base system where `index` and `target` are populated; default falls back to the instance of `S`.
- `index=nothing`: variables to construct index columns of the output; default falls back to `context.clock.time`.
- `target=nothing`: variables to construct non-index columns of the output; default includes most variables in the root instance.
- `meta=nothing`: name of systems in the configuration to be included in the output as metadata.

## Configuration
- `config=()`: a single configuration for the system, or a base for multiple configurations (when used with `configs`).
- `configs=[]`: multiple configurations for the system.
- `seed=nothing`: random seed for resetting each simulation run.

## Progress
- `stop=nothing`: condition checked before calling updates for the instance; default stops with no update.
- `snap=nothing`: condition checked to decide if a snapshot of current update is saved in the output; default snaps all updates.
- `snatch=nothing`: callback for modifying intermediate output; list of DataFrame `D` collected from current update and the instance of system `s` are provided.
- `verbose=true`: shows a progress bar.

## Format
- `nounit=false`: remove units from the output.
- `long=false`: convert output table from wide to long format.

# Examples
```julia-repl
julia> @system S(Controller) begin
           a => 1 ~ preserve(parameter)
           b(a) ~ accumulate
       end;

julia> simulate(S; stop=1)
2×3 DataFrame
 Row │ time       a        b
     │ Quantity…  Float64  Float64
─────┼─────────────────────────────
   1 │    0.0 hr      1.0      0.0
   2 │    1.0 hr      1.0      1.0
```
"""
simulate(; system, kw...) = simulate(system; kw...)
simulate(S::Type{<:System}; base=nothing, index=nothing, target=nothing, meta=nothing, kwargs...) = begin
    simulate(S, [(; base, index, target, meta)]; kwargs...) |> only
end
simulate(S::Type{<:System}, layout::Vector; config=(), configs=[], options=(), seed=nothing, kwargs...) = begin
    if isempty(configs)
        s = instance(S; config, options, seed)
        simulate!(s, layout; kwargs...)
    else
        simulate(S, layout, @config(config + configs); options, seed, kwargs...)
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

export simulate, simulate!
