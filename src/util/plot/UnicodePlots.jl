import UnicodePlots

plot2!(::Val{:UnicodePlots}, p::Union{Plot,Nothing}, X, Ys; kind, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, xunit, yunit, aspect, width=40, height=15) = begin
    canvas = if get(ENV, "CI", nothing) == "true"
        UnicodePlots.DotCanvas
    else
        UnicodePlots.BrailleCanvas
    end

    if kind == :line || kind == :scatterline
        plot! = UnicodePlots.lineplot!
    elseif kind == :scatter
        plot! = UnicodePlots.scatterplot!
    else
        error("unrecognized plot kind = $kind")
    end

    !isnothing(legendpos) && @warn "unsupported legend position = $legendpos"

    create_colors(colors; n0=0) = begin
        n = length(colors)
        C = collect(Iterators.take(Iterators.cycle(UnicodePlots.color_cycle), n+n0))[n0+begin:end]
        f(c::Int, _) = p.opt[:colors][c]
        f(c, _) = c in keys(UnicodePlots.color_encode) ? c : :normal
        f(::Nothing, i) = C[i]
        [f(c, i) for (i, c) in enumerate(colors)]
    end

    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    !endswith(xlab, "\n") && (xlab *= "\n")

    #HACK: handle x-axis type of Date/DateTime adapted from UnicodePlots.lineplot()
    xlim_value(v::Dates.TimeType) = Dates.value(v)
    xlim_value(v) = v
    xlimval = xlim_value.(xlim)

    if isnothing(p)
        a = Float64[]
        !isnothing(aspect) && (width = round(Int, aspect * 2height))
        obj = UnicodePlots.Plot(a, a, canvas; title, xlabel=xlab, ylabel=ylab, xlim=xlimval, ylim, width, height)
        UnicodePlots.annotate!(obj, :r, legend)
        #HACK: override xlim string (for Date/DateTime)
        UnicodePlots.annotate!(obj, :bl, string(xlim[1]), color=:light_black)
        UnicodePlots.annotate!(obj, :br, string(xlim[2]), color=:light_black)
        p = Plot(obj; Xs=[], Ys=[], kinds=[], colors=[], title, xlab, ylab, legend, names, xlim, ylim, xunit, yunit, aspect, width, height)
    end
    colors = create_colors(colors; n0=length(p.opt[:Ys]))
    for (i, (Y, name)) in enumerate(zip(Ys, names))
        #HACK: UnicodePlots can't handle missing
        Y = coalesce.(Y, NaN)
        color = colors[i]
        plot!(p.obj, X, Y; name, color)
        #TODO: remember colors
        update!(p; Xs=[X], Ys=[Y], kinds=[kind], colors=[color])
    end
    p
end

plot3!(::Val{:UnicodePlots}, X, Y, Z; kind, title, legend, legendpos, xlab, ylab, zlab, xlim, ylim, zlim, zgap, zlabgap, aspect, width=0, height=30) = begin
    if kind == :heatmap
        ;
    elseif kind == :contour
        @warn "unsupported plot kind = $kind"
    else
        error("unrecognized plot kind = $kind")
    end

    !legend && @warn "unsupported legend = $legend"
    !isnothing(legendpos) && @warn "unsupported legend position = $legendpos"

    !isnothing(zgap) && @warn "unsupported contour interval = $zgap"
    !isnothing(zlabgap) && @warn "unsupported countour label interval = $zlabgap"

    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    !endswith(xlab, "\n") && (xlab *= "\n")

    arr(a) = sort(unique(a))
    x = arr(X)
    y = arr(Y)
    M = reshape(Z, length(y), length(x))

    offset(a) = a[1]
    xoffset = offset(x)
    yoffset = offset(y)
    scale(a) = (a[end] - offset(a)) / (length(a) - 1)
    xscale = scale(x)
    yscale = scale(y)

    !isnothing(aspect) && (width = round(Int, aspect * height))

    #TODO: support zlim (minz/maxz currentyl fixed in UnicodePlots)
    obj = UnicodePlots.heatmap(M; title, xlabel=xlab, ylabel=ylab, zlabel=zlab, xscale, yscale, xlim, ylim, xoffset, yoffset, width, height)
    Plot(obj; X, Y, Z, kind, title, xlab, ylab, zlab, xlim, ylim, zlim, aspect, width, height)
end
