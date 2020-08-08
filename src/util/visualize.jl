@nospecialize

visualize(S::Type{<:System}, x, y;
    config=(), group=(), xstep=(),
    stop=nothing, skipfirst=true, filter=nothing,
    ylab=nothing, legend=nothing, names=nothing, plotopts...
) = begin
    G = configure(group)
    C = @config config + !G
    n = length(C)

    legend!(k, S) = begin
        isnothing(legend) && (legend = string(k))
        #TODO: support custom unit for legend?
        u = vartype(S, k) |> unittype
        !isnothing(u) && (legend *= " ($u)")
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
    isnothing(ylab) && (ylab = y)

    s(c) = simulate(S; configs=@config(c + !xstep), stop=stop, skipfirst=skipfirst, filter=filter, verbose=false)
    r = s(C[1])
    p = plot(r, x, y; ylab=ylab, legend=legend, name=names[1], plotopts...)
    for i in 2:n
        r = s(C[i])
        p = plot!(p, r, x, y; name=names[i], plotopts...)
    end
    p
end
visualize(S::Type{<:System}, x, y::Vector;
    config=(), xstep=(),
    stop=nothing, skipfirst=true, filter=nothing,
    plotopts...
) = begin
    r = simulate(S; configs=@config(config + !xstep), stop=stop, skipfirst=skipfirst, filter=filter, verbose=false)
    plot(r, x, y; plotopts...)
end

visualize(df::DataFrame, S::Type{<:System}, x, y; config=(), kw...) = visualize(df, [S], x, y; configs=[config], kw...)
visualize(df::DataFrame, SS::Vector, x, y;
    configs=[], xstep=(),
    stop=nothing, skipfirst=true, filter=nothing,
    xlab=nothing, ylab=nothing, name=nothing, names=nothing, xunit=nothing, yunit=nothing, plotopts...
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
    isnothing(names) && (names = nameof.(SS))

    p = plot(df, xo, yo; kind=:scatter, name=name, xlab=xlab, ylab=ylab, xunit=xunit, yunit=yunit, plotopts...)
    for (S, c, name) in zip(SS, configs, names)
        cs = isnothing(xstep) ? c : @config(c + !xstep)
        r = simulate(S; configs=cs, stop=stop, skipfirst=skipfirst, filter=filter, verbose=false)
        p = plot!(p, r, xe, ye; kind=:line, name=name, xunit=xunit, yunit=yunit, plotopts...)
    end
    p
end
visualize(df::DataFrame, S::Type{<:System}, y;
    configs=[],
    stop=nothing, skipfirst=true, filter=nothing,
    title=nothing, xlab=nothing, ylab=nothing, lim=nothing, plotopts...
) = begin
    y = y isa Pair ? y : y => y
    yo, ye = y
    xlab = isnothing(xlab) ? yo : xlab
    ylab = isnothing(ylab) ? ye : ylab
    isnothing(title) && (title = yo == ye ? string(yo) : "$yo : $ye")

    X = extractarray(df, yo)
    r = simulate(S; configs=configs, stop=stop, skipfirst=skipfirst, filter=filter, verbose=false)
    Y = extractarray(r, ye)

    if isnothing(lim)
        l = findlim.(deunitfy.([X, Y]))
        lim = (minimum(l)[1], maximum(l)[2])
    end
    I = [lim[1], lim[2]]

    p = plot(X, Y; kind=:scatter, title=title, name="", xlab=xlab, ylab=ylab, xlim=lim, ylim=lim, aspect=1, plotopts...)
    !isnothing(lim) && plot!(p, I, I, kind=:line, name="")
    p
end

visualize(S::Type{<:System}, x, y, z;
    config=(), xstep=(), ystep=(),
    stop=nothing, skipfirst=true, filter=nothing,
    plotopts...
) = begin
    C = @config config + xstep * ystep
    r = simulate(S; configs=C, stop=stop, skipfirst=skipfirst, filter=filter, verbose=false)
    plot(r, x, y, z; plotopts...)
end

@specialize

export visualize
