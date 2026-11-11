"""
    visualize(<arguments>; <keyword arguments>) -> Plot

Visualize existing arrays or a DataFrame, or run the necessary simulations and visualize their output.
With only a system type, `visualize(S; kind=:dependency)` instead returns a
static structural graph; use `kind=:hierarchy` for system composition.

See also: [`visualize!`](@ref), [`simulate`](@ref), [`manipulate`](@ref)

# Examples
```julia-repl
julia> @system S(Controller) begin
           a(a) => a ~ accumulate(init=1)
       end;

julia> visualize(S, :time, :a; stop=5, kind=:line)
       ┌────────────────────────────────────────┐
    32 │                                       :│
       │                                      : │
       │                                     :  │
       │                                    :   │
       │                                   :    │
       │                                  :     │
       │                                 :      │
  a    │                                :       │
       │                              .'        │
       │                            .'          │
       │                          .'            │
       │                       ..'              │
       │                   ..''                 │
       │             ....''                     │
     1 │.........''''                           │
       └────────────────────────────────────────┘
       0                                        5
                      time (hr)
```
"""
visualize(a...; kw...) = plot(a...; kw...)

"""
    visualize(S::Type{<:System}; kind=:dependency) -> Graph
    visualize(S::Type{<:System}, selector; kind=:dependency, depth=1, direction=:both) -> Dependency

Show a system's declared structure without running a simulation. `kind` is
`:dependency` for variables and their generated update stages, or `:hierarchy`
for system composition and mixins. The hierarchy omits nested `Context`
infrastructure. Simulation plots still use `visualize(S, x, y; ...)`.

For dependency graphs, a selector may be a variable name, a `source => target`
pair, or a vector combining names and pairs. Names select neighborhoods:
`depth=0` keeps only the named variables, and each additional level crosses one
variable boundary. `direction` is `:up` for inputs, `:down` for affected variables,
or `:both`. Pairs select every directed path between their endpoints, independent
of `depth` and `direction`; each endpoint may also be a vector of names.
Several selectors combine their results. Unknown names and pairs with no path
raise an `ArgumentError`.
Paths follow generated update stages and do not cross from a state's
post-update stage to its main stage in the next timestep.

`[:a, :c]` selects the union of two neighborhoods, which may be disconnected or
include side branches. `:a => :c` selects the connecting paths regardless of
their length, without off-path neighbors. Both retain all generated phases of
included variables and configuration sources for included parameters. Selected
names and path endpoints are emphasized in bold.

The returned graph has a text representation in a terminal and an SVG display
in notebooks. Use [`Cropbox.writeimage`](@ref) to save an image, or
[`Cropbox.writedot`](@ref) for renderer-independent Graphviz source. Rendering
options, such as `style=(group=:system,)`, belong to these export functions.

# Examples
```julia
visualize(GrowingDegree)
visualize(GrowingDegree; kind=:hierarchy)
visualize(GrowingDegree, :r; depth=2, direction=:up)
visualize(GrowingDegree, [:T, :r])
visualize(GrowingDegree, :T => :r)
visualize(GrowingDegree, [:Tb, :T => :r])
```
"""
visualize(S::Type{<:System}; kind=:dependency) = begin
    kind == :dependency && return dependency(S)
    kind == :hierarchy && return hierarchy(S; skipcontext=true)
    throw(ArgumentError("structure kind must be :dependency or :hierarchy"))
end
visualize(S::Type{<:System}, selector::Union{Symbol,Pair,AbstractVector};
    kind=:dependency, depth::Integer=1, direction=:both,
) = begin
    kind == :dependency || throw(ArgumentError("variable selectors require kind=:dependency"))
    selectors = selector isa AbstractVector ? selector : [selector]
    selectiondependency(dependency(S), selectors; depth, direction)
end

"""
    visualize!(p, <arguments>; <keyword arguments>) -> Plot

Update an existing `Plot` object `p` by appending a plot layer made with `visualize`.
This operation does not apply to structural graphs.

See also: [`visualize`](@ref)

# Arguments
- `p::Union{Plot,Nothing}`: plot object to be updated; `nothing` creates a new plot.
"""
visualize!(a...; kw...) = plot!(a...; kw...)

"""
    visualize!(p::Plot, x, y::Number, text::AbstractString; color=nothing, align=:left)

Add text at data coordinates without changing axis limits or the legend.
Coordinates use the existing axis units; compatible unitful values are converted.
The horizontal coordinate also accepts `Date` or `DateTime` on a calendar axis.
`align` is `:left`, `:center`, or `:right`. Newlines separate multiple lines of text.
"""
visualize!(p::Plot, x::Union{Number,Dates.TimeType}, y::Number, text::AbstractString; color=nothing, align=:left) = begin
    align in (:left, :center, :right) || throw(ArgumentError("unsupported text alignment: $align"))
    x = deunitfy(x, getplotopt(p, :xunit))
    y = deunitfy(y, getplotopt(p, :yunit))
    plottext!(Val(detectbackend(p)), p, x, y, text; color, align)
end

visualize(S::Type{<:System}, x, y; kw...) = visualize!(nothing, S, x, y; kw...)
visualize!(p, S::Type{<:System}, x, y;
    config=(), group=(), xstep=(),
    base=nothing,
    stop=nothing, snap=nothing,
    ylab=nothing, legend=nothing, names=nothing, colors=nothing, plotopts...
) = begin
    G = configure(group)
    C = @config config + !G
    n = length(C)

    legend!(k, S) = begin
        isnothing(legend) && (legend = string(k))
        #TODO: support custom unit for legend?
        u = vartype(S, k) |> unittype
        legend = label(legend, u)
    end

    #HACK: support indirect referencing of label by variable name
    names = if names isa Symbol
        k = names
        legend!(k, S)
        repeat([k], n)
    elseif !isnothing(names)
        names
    elseif isempty(G)
        [""]
    elseif G isa Vector
        # temporary numeric labels
        string.(1:n)
    else
        K, V = only(G)
        k, v = only(V)
        T = K == Symbol(0) ? S : typefor(K, scopeof(S))
        legend!(k, T)
        string.(v)
    end
    checklengths(n; names, colors)
    isnothing(colors) && (colors = repeat([nothing], n))
    isnothing(ylab) && (ylab = y)

    s(c) = simulate(S; base, target=[x, y], configs=@config(c + !xstep), stop, snap, verbose=false)
    data = (s(c) for c in C)
    if isnothing(p) && plotbackend(p, get(plotopts, :backend, nothing)) == :UnicodePlots
        data = collect(data)
    end
    limits = groupplotlimits(p, data, x, [y]; plotopts...)
    for (i, r) in enumerate(data)
        p = plot!(p, r, x, y; ylab, legend, name = names[i], color = colors[i], plotopts..., limits...)
    end
    p
end

visualize(SS::Vector, x, y; kw...) = visualize!(nothing, SS, x, y; kw...)
visualize!(p, SS::Vector, x, y; configs=[], names=nothing, colors=nothing, kw...) = begin
    n = length(SS)
    checklengths(n; names, colors)
    isempty(configs) && (configs = repeat([()], n))
    @assert length(configs) == n
    isnothing(names) && (names = string.(nameof.(SS)))
    isnothing(colors) && (colors = repeat([nothing], n))

    for (S, config, name, color) in zip(SS, configs, names, colors)
        p = visualize!(p, S, x, y; config, name, color, kw...)
    end
    p
end

visualize(S::Type{<:System}, x, y::Vector; kw...) = visualize!(nothing, S, x, y; kw...)
visualize!(p, S::Type{<:System}, x, y::Vector;
    config=(), xstep=(),
    base=nothing,
    stop=nothing, snap=nothing,
    plotopts...
) = begin
    r = simulate(S; base, target=[x, y], configs=@config(config + !xstep), stop, snap, verbose=false)
    plot!(p, r, x, y; plotopts...)
end

visualize(df::DataFrame, S::Type{<:System}, x, y; kw...) = visualize!(nothing, df, S, x, y; kw...)
visualize!(p, df::DataFrame, S::Type{<:System}, x, y; config=(), kw...) = visualize!(p, df, [S], x, y; configs=[config], kw...)
visualize(df::DataFrame, SS::Vector, x, y; kw...) = visualize!(nothing, df, SS, x, y; kw...)
visualize!(p, df::DataFrame, SS::Vector, x, y;
    configs=[], xstep=(),
    base=nothing,
    stop=nothing, snap=nothing,
    xlab=nothing, ylab=nothing, name=nothing, names=nothing, colors=nothing, xunit=nothing, yunit=nothing, plotopts...
) = begin
    x = x isa Pair ? x : x => x
    y = y isa Pair ? y : y => y
    xo, xe = x
    yo, ye = y
    xlab = isnothing(xlab) ? xe : xlab
    ylab = isnothing(ylab) ? ye : ylab

    u(n) = extractunit(df, n)
    isnothing(xunit) && (xunit = u(xo))
    isnothing(yunit) && (yunit = u(yo))

    n = length(SS)
    checklengths(n; names, colors)
    isempty(configs) && (configs = repeat([()], n))
    @assert length(configs) == n
    isnothing(names) && (names = string.(nameof.(SS)))
    isnothing(colors) && (colors = repeat([nothing], n))

    p = plot!(p, df, xo, yo; kind=:scatter, name, xlab, ylab, xunit, yunit, plotopts...)
    for (S, c, name, color) in zip(SS, configs, names, colors)
        cs = isnothing(xstep) ? c : @config(c + !xstep)
        r = simulate(S; base, target=[xe, ye], configs=cs, stop, snap, verbose=false)
        p = plot!(p, r, xe, ye; kind=:line, name, color, xunit, yunit, plotopts...)
    end
    p
end

visualize(obs::AbstractDataFrame, est::AbstractDataFrame, y; kw...) = visualize!(nothing, obs, est, y; kw...)
visualize!(p, obs::AbstractDataFrame, est::AbstractDataFrame, y; name = "", group = nothing, kw...) =
    visualize!(p, obs, est, [y]; group, names = !isnothing(group) && name == "" ? nothing : [name], kw...)
visualize!(p, obs::AbstractDataFrame, est::AbstractDataFrame, y::Vector;
    index, group = nothing, names = nothing, colors = nothing, legend = nothing, plotopts...
) = begin
    targets = [string(o) == string(e) ? "$o" : "$o ⇒ $e" for (o, e) in parsetarget(y, obs)]
    if isnothing(group)
        Xs, Ys = aligndata(obs, est, y; index)
        isnothing(names) && (names = targets)
    else
        groups, names, legend = preparegroups(est, targets; group, names, legend)
        common = intersect(DataFrames.groupcols(groups), propertynames(obs))
        data = map(pairs(groups)) do (key, d)
            o = isempty(common) ? obs : filter(r -> all(k -> indexequal(r[k], key[k]), common), obs; view = true)
            aligndata(o, d, y; index)
        end
        Xs, Ys = vcat(first.(data)...), vcat(last.(data)...)
    end
    _visualize_obs_vs_est!(p, Xs, Ys; names, colors, legend, plotopts...)
end

visualize(obs::DataFrame, S::Type{<:System}, y::Vector; kw...) = visualize!(nothing, obs, S, y; kw...)
visualize!(p, obs::DataFrame, S::Type{<:System}, y::Vector;
    index,
    config=(), configs=[],
    base=nothing,
    stop=nothing, snap=nothing,
    names=nothing, plotopts...
) = begin
    I = parseindex(index, S) |> keys |> collect
    Ye = parsetarget(y, S) |> values |> collect
    est = simulate(S; config, configs, base, index, target=Ye, stop, snap, verbose=false)
    visualize!(p, obs, est, y; index = I, names, plotopts...)
end

visualize(obs::DataFrame, S::Type{<:System}, y; kw...) = visualize!(nothing, obs, S, y; kw...)
visualize!(p, obs::DataFrame, S::Type{<:System}, y; config=(), configs=[], name="", kw...) = visualize!(p, obs, [(; system=S, config, configs)], y; names=[name], kw...)
visualize(obs::DataFrame, maps::Vector{<:NamedTuple}, y; kw...) = visualize!(nothing, obs, maps, y; kw...)
visualize!(p, obs::DataFrame, maps::Vector{<:NamedTuple}, y;
    index,
    config=(), configs=[],
    base=nothing,
    stop=nothing, snap=nothing,
    names=nothing, plotopts...
) = begin
    I = parseindex(index, obs) |> keys |> collect
    ye = parsetarget(y, obs) |> values |> only

    ests = map(m -> simulate(; m..., base, index, target=ye, stop, snap, verbose=false), maps)
    data = [aligndata(obs, est, y; index = I) for est in ests]
    Xs = [only(X) for (X, Y) in data]
    Ys = [only(Y) for (X, Y) in data]

    isnothing(names) && (names = ["$(m.system)" for m in maps])

    _visualize_obs_vs_est!(p, Xs, Ys; names, plotopts...)
end

_visualize_obs_vs_est!(p, Xs, Ys; xlab=nothing, ylab=nothing, names=nothing, colors=nothing, lim=nothing, plotopts...) = begin
    Xs, Ys = convertcolumn.(Xs), convertcolumn.(Ys)
    isnothing(xlab) && (xlab = "Observation")
    isnothing(ylab) && (ylab = "Model")

    n = length(Ys)
    checklengths(n; names, colors)
    isnothing(names) && (names = repeat([""], n))
    isnothing(colors) && (colors = repeat([nothing], n))

    if isnothing(lim)
        lim = findlim(vcat(deunitfy.([Xs..., Ys...])...))
    end
    L = [lim[1], lim[2]]

    for (X, Y, name, color) in zip(Xs, Ys, names, colors)
        p = plot!(p, X, Y; kind = :scatter, name, color, xlab, ylab, xlim = lim, ylim = lim, aspect = 1, plotopts...)
    end
    color = detectbackend(p) == :UnicodePlots ? :light_gray : :lightgray
    plot!(p, L, L; kind = :line, color, name = "")
    p
end

visualize(S::Type{<:System}, x, y, z;
    config=(), xstep=(), ystep=(),
    base=nothing,
    stop=nothing, snap=nothing,
    plotopts...
) = begin
    configs = @config config + xstep * ystep
    r = simulate(S; base, index=[x, y], target=z, configs, stop, snap, verbose=false)
    plot(r, x, y, z; plotopts...)
end

visualize_call(S::Type{<:System}, x, y, call...; config=(), xstep=(), plotopts...) = begin
    if isempty(xstep)
        s = instance(S; config)
        f = s[y]'
        i = findall(a -> a isa AbstractRange || a isa AbstractArray, call) |> only
        rx = call[i] |> collect
        ry = [f(a...) for a in Iterators.product(call...)]
        plot(rx, ry; xlab=x, ylab=y, plotopts...)
    else
        configs = @config(config + !xstep)
        r(c) = begin
            s = instance(S; config=c)
            f = s[y]'
            (s[x]', f(call...))
        end
        l = [r(c) for c in configs]
        rx, ry =  [first.(l), last.(l)]
        plot(rx, ry; xlab=x, ylab=y, plotopts...)
    end
end

export visualize, visualize!
