import DataFrames: DataFrame
import Gadfly
import UnicodePlots
import Unitful

plot(df::DataFrame, index::Symbol, target::Symbol; legend=nothing, kw...) = plot(df, index, [target]; legend=[legend], kw...)
plot(df::DataFrame, index::Symbol, target::Vector{Symbol}; kw...) = plot!(nothing, df, index, target; kw...)
plot!(p, df::DataFrame, index::Symbol, target::Symbol; legend=nothing, kw...) = plot!(p, df, index, [target]; legend=[legend], kw...)
plot!(p, df::DataFrame, index::Symbol, target::Vector{Symbol}; kind=:scatter, title=nothing, xlabel=nothing, ylabel=nothing, legend=nothing, xlim=nothing, ylim=nothing) = begin
    u(n) = unit(eltype(df[!, n]))
    xu = u(index)
    yu = Unitful.promote_unit(u.(target)...)

    #HACK: Gadfly doesn't handle missing properly: https://github.com/GiovineItalia/Gadfly.jl/issues/1267
    arr(n::Symbol, u) = coalesce.(deunitfy.(df[!, n], u), NaN)
    X = arr(index, xu)
    Ys = arr.(target, yu)
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

    lab(l, u) = Unitful.isunitless(u) ? "$l" : "$l ($u)"
    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    xlab = lab(isnothing(xlabel) ? index : xlabel, xu) * '\n'
    ylab = lab(isnothing(ylabel) ? "" : ylabel, yu)

    legs = isnothing(legend) ? repeat([nothing], n) : legend
    leg(t, l) = string(isnothing(l) ? t : l)
    names = [leg(t, l) for (t, l) in zip(target, legs)]

    title = isnothing(title) ? "" : string(title)

    if isdefined(Main, :IJulia) && Main.IJulia.inited
        if kind == :line
            geom = Gadfly.Geom.line
        elseif kind == :scatter
            geom = Gadfly.Geom.point
        else
            error("unrecognized plot kind = $kind")
        end

        if isnothing(p)
            colors = Gadfly.Scale.default_discrete_colors(n)
            layers = [Gadfly.layer(x=X, y=Ys[i], geom, Gadfly.Theme(default_color=colors[i])) for i in 1:n]
            Gadfly.plot(
                Gadfly.Coord.cartesian(xmin=xlim[1], ymin=ylim[1], xmax=xlim[2], ymax=ylim[2]),
                Gadfly.Guide.title(title),
                Gadfly.Guide.xlabel(xlab),
                Gadfly.Guide.ylabel(ylab),
                Gadfly.Guide.manual_color_key("", names, colors),
                layers...
            )
        else
            #TODO: very hacky approach to append new plots... definitely need a better way
            n0 = length(p.layers)
            colors = Gadfly.Scale.default_discrete_colors(n0 + n)
            layers = [Gadfly.layer(x=X, y=Ys[i], geom, Gadfly.Theme(default_color=colors[n0 + i])) for i in 1:n]
            #HACK: extend ManualColorKey with new elements
            mck = p.guides[end]
            for (c, l) in zip(colors[n0+1:end], names)
                mck.labels[c] = l
            end
            Gadfly.plot(
                p.coord,
                p.guides...,
                p.layers...,
                layers...
            )
        end
    else
        canvas = if get(ENV, "GITHUB_ACTIONS", "false") == "true"
            UnicodePlots.DotCanvas
        else
            UnicodePlots.BrailleCanvas
        end

        if kind == :line
            plot = UnicodePlots.lineplot
            plot! = UnicodePlots.lineplot!
        elseif kind == :scatter
            plot = UnicodePlots.scatterplot
            plot! = UnicodePlots.scatterplot!
        else
            error("unrecognized plot kind = $kind")
        end

        if isnothing(p)
            a = Float64[]
            p = UnicodePlots.Plot(a, a, canvas; title=title, xlabel=xlab, ylabel=ylab, xlim=xlim, ylim=ylim)
        end
        for i in 1:n
            plot!(p, X, Ys[i], name=names[i])
        end
        p
    end
end
