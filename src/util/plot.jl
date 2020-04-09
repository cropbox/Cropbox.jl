import DataFrames: DataFrame
import Gadfly
import UnicodePlots
import Unitful

plot(df::DataFrame, x::Symbol, y::Symbol; name=nothing, kw...) = plot(df, x, [y]; name=[name], kw...)
plot(df::DataFrame, x::Symbol, y::Vector{Symbol}; kw...) = plot!(nothing, df, x, y; kw...)
plot!(p, df::DataFrame, x::Symbol, y::Symbol; name=nothing, kw...) = plot!(p, df, x, [y]; name=[name], kw...)
plot!(p, df::DataFrame, x::Symbol, y::Vector{Symbol}; kind=:scatter, title=nothing, xlab=nothing, ylab=nothing, legend=nothing, name=nothing, xlim=nothing, ylim=nothing, backend=nothing) = begin
    u(n) = unit(eltype(df[!, n]))
    xu = u(x)
    yu = Unitful.promote_unit(u.(y)...)

    #HACK: Gadfly doesn't handle missing properly: https://github.com/GiovineItalia/Gadfly.jl/issues/1267
    arr(n::Symbol, u) = coalesce.(deunitfy.(df[!, n], u), NaN)
    X = arr(x, xu)
    Ys = arr.(y, yu)
    n = length(Ys)

    lim(a) = let a = filter(!isnan, a), #HACK: lack of missing support in Gadfly
                 l = isempty(a) ? 0 : floor(minimum(a)),
                 u = isempty(a) ? 0 : ceil(maximum(a))
        #HACK: avoid empty range
        l == u ? (l, l+1) : (l, u)
    end
    isnothing(xlim) && (xlim = lim(X))
    if isnothing(ylim)
        l = lim.(Ys)
        ylim = (minimum(l)[1], maximum(l)[2])
    end

    #HACK: add whitespace to make Pango happy and avoid text clipping
    lab(l, u) = Unitful.isunitless(u) ? " $l " : " $l ($u) "
    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    xlab = lab(isnothing(xlab) ? x : xlab, xu) * '\n'
    ylab = lab(isnothing(ylab) ? "" : ylab, yu)
    legend = isnothing(legend) ? "" : string(legend)
    name = isnothing(name) ? repeat([nothing], n) : name
    names = [string(isnothing(l) ? t : l) for (t, l) in zip(y, name)]
    title = isnothing(title) ? "" : string(title)

    if isnothing(backend)
        backend = if isdefined(Main, :IJulia) && Main.IJulia.inited
            :Gadfly
        else
            :UnicodePlots
        end
    end
    plot2!(Val(backend), p, X, Ys; kind=kind, title=title, xlab=xlab, ylab=ylab, legend=legend, names=names, xlim=xlim, ylim=ylim)
end

plot(df::DataFrame, x::Symbol, y::Symbol, z::Symbol; kind=:heatmap, title=nothing, xlab=nothing, ylab=nothing, zlab=nothing, xlim=nothing, ylim=nothing, zlim=nothing, backend=nothing) = begin
    #TODO: share code with plot!() above
    u(n) = unit(eltype(df[!, n]))
    xu = u(x)
    yu = u(y)
    zu = u(z)

    #HACK: Gadfly doesn't handle missing properly: https://github.com/GiovineItalia/Gadfly.jl/issues/1267
    arr(n::Symbol, u) = coalesce.(deunitfy.(df[!, n], u), NaN)
    X = arr(x, xu)
    Y = arr(y, yu)
    Z = arr(z, zu)

    lim(a) = let a = filter(!isnan, a), #HACK: lack of missing support in Gadfly
                 l = isempty(a) ? 0 : floor(minimum(a)),
                 u = isempty(a) ? 0 : ceil(maximum(a))
        #HACK: avoid empty range
        l == u ? (l, l+1) : (l, u)
    end
    isnothing(xlim) && (xlim = lim(X))
    isnothing(ylim) && (ylim = lim(Y))
    isnothing(zlim) && (zlim = lim(Z))

    #HACK: add whitespace to make Pango happy and avoid text clipping
    lab(l, u) = Unitful.isunitless(u) ? " $l " : " $l ($u) "
    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    xlab = lab(isnothing(xlab) ? x : xlab, xu) * '\n'
    ylab = lab(isnothing(ylab) ? y : ylab, yu)
    zlab = lab(isnothing(zlab) ? z : zlab, zu)
    title = isnothing(title) ? "" : string(title)

    if isnothing(backend)
        backend = if isdefined(Main, :IJulia) && Main.IJulia.inited
            :Gadfly
        else
            :UnicodePlots
        end
    end
    plot3!(Val(backend), X, Y, Z; kind=kind, title=title, xlab=xlab, ylab=ylab, zlab=zlab, xlim=xlim, ylim=ylim, zlim=zlim)
end

plot2!(::Val{:Gadfly}, p, X, Ys; kind, title, xlab, ylab, legend, names, xlim, ylim) = begin
    n = length(Ys)

    if kind == :line
        geom = Gadfly.Geom.line
    elseif kind == :scatter
        geom = Gadfly.Geom.point
    else
        error("unrecognized plot kind = $kind")
    end

    theme = Gadfly.Theme(
        major_label_font_size=10*Gadfly.pt,
        key_title_font_size=9*Gadfly.pt,
    )

    if isnothing(p)
        colors = Gadfly.Scale.default_discrete_colors(n)
        layers = [Gadfly.layer(x=X, y=Ys[i], geom, Gadfly.Theme(default_color=colors[i])) for i in 1:n]
        p = Gadfly.plot(
            Gadfly.Coord.cartesian(xmin=xlim[1], ymin=ylim[1], xmax=xlim[2], ymax=ylim[2]),
            Gadfly.Guide.title(title),
            Gadfly.Guide.xlabel(xlab),
            Gadfly.Guide.ylabel(ylab),
            Gadfly.Guide.manual_color_key(legend, names, colors),
            layers...,
            theme,
        )
    else
        #TODO: very hacky approach to append new plots... definitely need a better way
        n0 = length(p.layers)
        colors = Gadfly.Scale.default_discrete_colors(n0 + n)
        #HACK: extend ManualColorKey with new elements
        mck = p.guides[end]
        for (c, l) in zip(colors[n0+1:end], names)
            mck.labels[c] = l
        end
        layers = [Gadfly.layer(x=X, y=Ys[i], geom, Gadfly.Theme(default_color=colors[n0 + i])) for i in 1:n]
        for l in layers
            Gadfly.push!(p, l)
        end
    end
    p
end

plot2!(::Val{:UnicodePlots}, p, X, Ys; kind, title, xlab, ylab, legend, names, xlim, ylim) = begin
    canvas = if get(ENV, "GITHUB_ACTIONS", "false") == "true"
        UnicodePlots.DotCanvas
    else
        UnicodePlots.BrailleCanvas
    end

    if kind == :line
        plot! = UnicodePlots.lineplot!
    elseif kind == :scatter
        plot! = UnicodePlots.scatterplot!
    else
        error("unrecognized plot kind = $kind")
    end

    if isnothing(p)
        a = Float64[]
        p = UnicodePlots.Plot(a, a, canvas; title=title, xlabel=xlab, ylabel=ylab, xlim=xlim, ylim=ylim)
        UnicodePlots.annotate!(p, :r, legend)
    end
    for (Y, name) in zip(Ys, names)
        plot!(p, X, Y; name=name)
    end
    p
end

plot3!(::Val{:Gadfly}, X, Y, Z; kind, title, xlab, ylab, zlab, xlim, ylim, zlim) = begin
    if kind == :heatmap
        geom = Gadfly.Geom.rectbin
    elseif kind == :contour
        geom = Gadfly.Geom.contour
    else
        error("unrecognized plot kind = $kind")
    end

    theme = Gadfly.Theme(
        major_label_font_size=10*Gadfly.pt,
        key_title_font_size=9*Gadfly.pt,
    )

    Gadfly.plot(
        x=X, y=Y,
        z=Z, color=Z, # z for contour, color for heatmap
        Gadfly.Coord.cartesian(xmin=xlim[1], ymin=ylim[1], xmax=xlim[2], ymax=ylim[2]),
        Gadfly.Guide.title(title),
        Gadfly.Guide.xlabel(xlab),
        Gadfly.Guide.ylabel(ylab),
        Gadfly.Guide.colorkey(title=zlab),
        Gadfly.Scale.color_continuous(minvalue=zlim[1], maxvalue=zlim[2]),
        geom,
        theme,
    )
end

plot3!(::Val{:UnicodePlots}, X, Y, Z; kind, title, xlab, ylab, zlab, xlim, ylim, zlim) = begin
    if kind == :heatmap
        ;
    elseif kind == :contour
        @warn "unsupported plot kind = $kind"
    else
        error("unrecognized plot kind = $kind")
    end

    arr(A) = sort(unique(A))
    x = arr(X)
    y = arr(Y)
    M = reshape(Z, length(x), length(y))'

    offset(a) = a[1]
    xoffset = offset(x)
    yoffset = offset(y)
    scale(a) = (a[end] - offset(a)) / (length(a) - 1)
    xscale = scale(x)
    yscale = scale(y)

    #TODO: support zlim (minz/maxz currentyl fixed in UnicodePlots)
    UnicodePlots.heatmap(M; title=title, xlabel=xlab, ylabel=ylab, zlabel=zlab, xscale=xscale, yscale=yscale, xlim=xlim, ylim=ylim, xoffset=xoffset, yoffset=yoffset)
end

visualize(S::Type{<:System}, x, y;
    config=(), group=(), xstep=(),
    stop=nothing, skipfirst=false, callback=nothing,
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

visualize(df::DataFrame, S::Type{<:System}, x, y; config=(), kw...) = visualize(df, [S], x, y; configs=[config], kw...)
visualize(df::DataFrame, SS::Vector, x, y;
    configs=(), xstep=(),
    stop=nothing, skipfirst=true, callback=nothing,
    xlab=nothing, ylab=nothing, names=nothing, plotopts...
) = begin
    x = x isa Pair ? x : x => x
    y = y isa Pair ? y : y => y
    xo, xe = x
    yo, ye = y
    xlab = isnothing(xlab) ? xe : xlab
    ylab = isnothing(ylab) ? ye : ylab

    n = length(SS)
    isempty(configs) && (configs = repeat([()], n))
    @assert length(configs) == n
    isnothing(names) && (names = nameof.(SS))

    p = plot(df, xo, yo; kind=:scatter, xlab=xlab, ylab=ylab, plotopts...)
    for (S, c, name) in zip(SS, configs, names)
        r = simulate(S; configs=configexpand(xstep, c), stop=stop, skipfirst=skipfirst, callback=callback)
        p = plot!(p, r, xe, ye; kind=:line, name=name, plotopts...)
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
