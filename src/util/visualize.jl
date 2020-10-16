@nospecialize

visualize(S::Type{<:System}, x, y; kw...) = visualize!(nothing, S, x, y; kw...)
visualize!(p, S::Type{<:System}, x, y;
    config=(), group=(), xstep=(),
    stop=nothing, skipfirst=true, snap=nothing,
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

    s(c) = simulate(S; configs=@config(c + !xstep), stop, skipfirst, snap, verbose=false)
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
    stop=nothing, skipfirst=true, snap=nothing,
    plotopts...
) = begin
    r = simulate(S; configs=@config(config + !xstep), stop, skipfirst, snap, verbose=false)
    plot!(p, r, x, y; plotopts...)
end

visualize(df::DataFrame, S::Type{<:System}, x, y; kw...) = visualize!(nothing, df, S, x, y; kw...)
visualize!(p, df::DataFrame, S::Type{<:System}, x, y; config=(), kw...) = visualize!(p, df, [S], x, y; configs=[config], kw...)
visualize(df::DataFrame, SS::Vector, x, y; kw...) = visualize!(nothing, df, SS, x, y; kw...)
visualize!(p, df::DataFrame, SS::Vector, x, y;
    configs=[], xstep=(),
    stop=nothing, skipfirst=true, snap=nothing,
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
        r = simulate(S; configs=cs, stop, skipfirst, snap, verbose=false)
        p = plot!(p, r, xe, ye; kind=:line, name, color, xunit, yunit, plotopts...)
    end
    p
end
visualize(df::DataFrame, S::Type{<:System}, y; kw...) = visualize!(nothing, df, S, y; kw...)
visualize!(p, df::DataFrame, S::Type{<:System}, y; configs=[], name="", kw...) = visualize!(p, df, [(; system=S, configs)], y; names=[name], kw...)
visualize(df::DataFrame, maps::Vector, y; kw...) = visualize!(nothing, df, maps, y; kw...)
visualize!(p, df::DataFrame, maps::Vector, y;
    stop=nothing, skipfirst=true, snap=nothing,
    xlab=nothing, ylab=nothing, names=nothing, colors=nothing, lim=nothing, plotopts...
) = begin
    y = y isa Pair ? y : y => y
    yo, ye = y
    xlab = isnothing(xlab) ? yo : xlab
    ylab = isnothing(ylab) ? ye : ylab

    X = extractarray(df, yo)
    Ys = map(maps) do m
        r = simulate(; m..., stop, skipfirst, snap, verbose=false)
        extractarray(r, ye)
    end

    n = length(Ys)
    isnothing(names) && (names = repeat([""], n))
    isnothing(colors) && (colors = repeat([nothing], n))

    if isnothing(lim)
        l = findlim.(deunitfy.([X, Ys...]))
        lim = (minimum(minimum.(l)), maximum(maximum.(l)))
    end
    L = [lim[1], lim[2]]

    p = plot!(p, X, Ys; kind=:scatter, names, xlab, ylab, xlim=lim, ylim=lim, aspect=1, plotopts...)
    !isnothing(lim) && plot!(p, L, L, kind=:line, color=:lightgray, name="")
    p
end

visualize(S::Type{<:System}, x, y, z;
    config=(), xstep=(), ystep=(),
    stop=nothing, skipfirst=true, snap=nothing,
    plotopts...
) = begin
    configs = @config config + xstep * ystep
    r = simulate(S; configs, stop, skipfirst, snap, verbose=false)
    plot(r, x, y, z; plotopts...)
end

@specialize

export visualize, visualize!
