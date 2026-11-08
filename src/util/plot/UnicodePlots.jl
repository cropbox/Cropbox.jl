import UnicodePlots

detectbackend(::Plot{<:UnicodePlots.Plot}) = :UnicodePlots

plot2!(::Val{:UnicodePlots}, p::Union{Plot,Nothing}, X, Ys; kind, linestyle, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, ycat, xunit, yunit, aspect, width=40, height=15) = begin
    isnothing(xlim) && (xlim = findlim(X))
    isnothing(ylim) && (ylim = findlim(vcat(Ys...)))
    canvas = if get(ENV, "CI", nothing) == "true"
        UnicodePlots.DotCanvas
    else
        UnicodePlots.BrailleCanvas
    end

    if kind == :line || kind == :scatterline
        plot! = UnicodePlots.lineplot!
    elseif kind == :scatter
        plot! = UnicodePlots.scatterplot!
    elseif kind == :step
        plot! = UnicodePlots.stairs!
        ycat = something(getplotopt(p, :ycat), ycat)
        all(in(ycat), Iterators.flatten(Ys)) || throw(ArgumentError("set ycat in the initial terminal plot to include every category"))
        #HACK: convert symbol array to integer index array
        ylim = (1, length(ycat))
        Ys = indexin.(Ys, Ref(ycat))
        height = length(ycat)
    elseif kind == :hline
        plot! = UnicodePlots.hline!
        #HACK: no clipping on x axis
        Ys = [nothing]
    elseif kind == :vline
        plot! = UnicodePlots.vline!
        #HACK: no clipping on y axis
        Ys = [nothing]
    else
        error("unrecognized plot kind = $kind")
    end

    !isnothing(legendpos) && @warn "unsupported legend position = $legendpos"
    all(==(:solid), linestyle isa AbstractVector ? linestyle : (linestyle,)) || @warn "UnicodePlots renders line style $linestyle as a solid line"

    create_colors(colors; n0=0) = begin
        n = length(colors)
        C = collect(Iterators.take(Iterators.cycle(UnicodePlots.COLOR_CYCLE[]), n+n0))[n0+begin:end]
        f(c::Int, _) = p.opt[:colors][c]
        f(c, _) = c
        f(::Nothing, i) = C[i]
        [f(c, i) for (i, c) in enumerate(colors)]
    end

    #HACK: handle x-axis type of Date/DateTime adapted from UnicodePlots.lineplot()
    xlim_value(v::Dates.TimeType) = Dates.value(v)
    xlim_value(v) = v
    xlimval = xlim_value.(xlim)

    annotate_x_axis!(obj) = begin
        #HACK: override xlim string (for Date/DateTime)
        UnicodePlots.label!(obj, :bl, string(xlim[1]), color=:dark_gray)
        UnicodePlots.label!(obj, :br, string(xlim[2]), color=:dark_gray)
    end

    annotate_y_axis!(obj) = begin
        if kind == :step
            #HACK: show original string of symbol instead of index number
            for (i, y) in zip(height:-1:1, ycat)
                UnicodePlots.label!(obj, :l, i, string(y), color=:dark_gray)
            end
        end
    end

    if isnothing(p)
        a = Float64[]
        !isnothing(aspect) && (width = round(Int, aspect * 2height))
        obj = UnicodePlots.Plot(a, a; canvas, title, xlabel=xlab, ylabel=ylab, xlim=xlimval, ylim, width, height)
        UnicodePlots.label!(obj, :r, legend)
        annotate_x_axis!(obj)
        annotate_y_axis!(obj)
        p = Plot(obj; Xs=[], Ys=[], kinds=[], colors=[], names=[], title, xlab, ylab, legend, legendpos, xlim, ylim, ycat, xunit, yunit, aspect, width, height)
    end
    colors = create_colors(colors; n0=length(p.opt[:Ys]))
    for (i, (Y, name)) in enumerate(zip(Ys, names))
        #HACK: UnicodePlots can't handle missing
        Y = coalesce.(Y, NaN)
        color = colors[i]
        plot!(p.obj, X, Y; name, color)
        #TODO: remember colors
        update!(p; Xs=[X], Ys=[Y], kinds=[kind], colors=[color], names=[name])
    end
    p
end

plot3!(::Val{:UnicodePlots}, X, Y, Z; kind, title, legend, legendpos, xlab, ylab, zlab, xlim, ylim, zlim, xunit, yunit, zunit, zgap, zlabgap, aspect, width=nothing, height=30) = begin
    kind in (:heatmap, :contour) || throw(ArgumentError("unrecognized plot kind = $kind"))

    !isnothing(legendpos) && @warn "unsupported legend position = $legendpos"

    !isnothing(zgap) && @warn "unsupported contour interval = $zgap"
    !isnothing(zlabgap) && @warn "unsupported countour label interval = $zlabgap"

    x, y, M = makegrid(X, Y, Z)
    M = permutedims(M)

    kind == :heatmap && (height = min(height, length(y)))
    !isnothing(aspect) && (width = round(Int, aspect * height))
    kind == :heatmap && !isnothing(width) && (width = min(width, length(x)))
    options = (; title, xlabel = xlab, ylabel = ylab, zlabel = zlab, xlim, ylim, zlim, colorbar = legend, width, height)
    obj = if kind == :heatmap
        fact(a) = length(a) == 1 ? 1 : (last(a) - first(a)) / (length(a) - 1)
        xfact, yfact = fact(x), fact(y)
        all(d -> isapprox(d, xfact), diff(x)) && all(d -> isapprox(d, yfact), diff(y)) ||
            throw(ArgumentError("terminal heatmaps require evenly spaced coordinates"))
        UnicodePlots.heatmap(M; options..., xfact, yfact, xoffset = first(x), yoffset = first(y))
    else
        length(x) > 1 && length(y) > 1 || throw(ArgumentError("contours require at least two coordinates on each axis"))
        UnicodePlots.contourplot(x, y, M; options...)
    end
    Plot(obj; X, Y, Z, kind, title, legend, legendpos, xlab, ylab, zlab, xlim, ylim, zlim, xunit, yunit, zunit, aspect, width, height)
end

plottext!(::Val{:UnicodePlots}, p, x, y, text; color, align) = begin
    color = isnothing(color) ? :normal : color
    lines = split(text, '\n')
    dy = UnicodePlots.height(p.obj.graphics) / UnicodePlots.nrows(p.obj.graphics)
    for (i, line) in enumerate(lines)
        yy = y + ((length(lines) + 1) / 2 - i) * dy
        UnicodePlots.annotate!(p.obj, x, yy, line; color, halign=align)
    end
    p
end
