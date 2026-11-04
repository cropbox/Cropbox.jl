"""
    visualize(<arguments>; <keyword arguments>) -> Plot

Visualize existing arrays or a DataFrame, or run the necessary simulations and visualize their output.

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
    visualize!(p, <arguments>; <keyword arguments>) -> Plot

Update an existing `Plot` object `p` by appending a new graph made with `visualize`.

See also: [`visualize`](@ref)

# Arguments
- `p::Union{Plot,Nothing}`: plot object to be updated; `nothing` creates a new plot.
"""
visualize!(a...; kw...) = plot!(a...; kw...)

"""
    visualize!(p::Plot, x::Number, y::Number, text::AbstractString; color=nothing, align=:left)

Add text at data coordinates without changing axis limits or the legend.
Coordinates use the existing axis units; compatible unitful values are converted.
`align` is `:left`, `:center`, or `:right`. Newlines separate multiple lines of text.
"""
visualize!(p::Plot, x::Number, y::Number, text::AbstractString; color=nothing, align=:left) = begin
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
    isnothing(colors) && (colors = repeat([nothing], n))
    isnothing(ylab) && (ylab = y)

    s(c) = simulate(S; base, target=[x, y], configs=@config(c + !xstep), stop, snap, verbose=false)
    r = s(C[1])
    p = plot!(p, r, x, y; ylab, legend, name=names[1], color=colors[1], plotopts...)
    for i in 2:n
        r = s(C[i])
        p = plot!(p, r, x, y; name=names[i], color=colors[i], plotopts...)
    end
    p
end

visualize(SS::Vector, x, y; kw...) = visualize!(nothing, SS, x, y; kw...)
visualize!(p, SS::Vector, x, y; configs=[], names=nothing, colors=nothing, kw...) = begin
    n = length(SS)
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
visualize!(p, obs::AbstractDataFrame, est::AbstractDataFrame, y; name = "", kw...) = visualize!(p, obs, est, [y]; names = [name], kw...)
visualize!(p, obs::AbstractDataFrame, est::AbstractDataFrame, y::Vector;
    index, names = nothing, plotopts...
) = begin
    Xs, Ys = aligndata(obs, est, y; index)
    isnothing(names) && (names = [string(o) == string(e) ? "$o" : "$o ⇒ $e" for (o, e) in parsetarget(y, obs)])
    _visualize_obs_vs_est!(p, Xs, Ys; names, plotopts...)
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
    isnothing(names) && (names = repeat([""], n))
    isnothing(colors) && (colors = repeat([nothing], n))

    if isnothing(lim)
        l = findlim.(deunitfy.([Xs..., Ys...]))
        lim = (minimum(minimum.(l)), maximum(maximum.(l)))
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
