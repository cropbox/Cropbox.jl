visualize(S::Type{<:System}, x, y;
    config=(), group=(), xstep=(),
    stop=nothing, skipfirst=true, callback=nothing,
    ylab=nothing, legend=nothing, plotopts...
) = begin
    G = configure(group)
    C = configexpand(G, config)

    if isempty(G)
        names = [""]
    else
        K, V = only(G)
        k, v = only(V)
        if isnothing(legend)
            T = K == Symbol(0) ? S : type(K)
            u = fieldtype(T, k) |> unit
            legend = isnothing(u) ? "$k" : "$k ($u)"
        end
        names = string.(v)
    end
    isnothing(ylab) && (ylab = y)

    s(c) = simulate(S; configs=configexpand(xstep, c), stop=stop, skipfirst=skipfirst, callback=callback)
    r = s(C[1])
    p = plot(r, x, y; ylab=ylab, legend=legend, name=names[1], plotopts...)
    for i in 2:length(C)
        r = s(C[i])
        p = plot!(p, r, x, y; name=names[i], plotopts...)
    end
    p
end
visualize(S::Type{<:System}, x, y::Vector;
    config=(), xstep=(),
    stop=nothing, skipfirst=true, callback=nothing,
    plotopts...
) = begin
    r = simulate(S; configs=configexpand(xstep, config), stop=stop, skipfirst=skipfirst, callback=callback)
    plot(r, x, y; plotopts...)
end

visualize(df::DataFrame, S::Type{<:System}, x, y; config=(), kw...) = visualize(df, [S], x, y; configs=[config], kw...)
visualize(df::DataFrame, SS::Vector, x, y;
    configs=[], xstep=(),
    stop=nothing, skipfirst=true, callback=nothing,
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
        r = simulate(S; configs=configexpand(xstep, c), stop=stop, skipfirst=skipfirst, callback=callback)
        p = plot!(p, r, xe, ye; kind=:line, name=name, xunit=xunit, yunit=yunit, plotopts...)
    end
    p
end

visualize(S::Type{<:System}, x, y, z;
    config=(), xstep=(), ystep=(),
    stop=nothing, skipfirst=true, callback=nothing,
    plotopts...
) = begin
    C = configmultiply([xstep, ystep], config)
    r = simulate(S; configs=C, stop=stop, skipfirst=skipfirst, callback=callback)
    plot(r, x, y, z; plotopts...)
end
