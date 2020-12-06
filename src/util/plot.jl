using DataFrames: DataFrame
import Gadfly
using MacroTools: @capture
import UnicodePlots
import Unitful

struct Plot
    obj
    opt::Dict{Symbol,Any}
    Plot(obj; kw...) = new(obj, Dict(kw...))
end
update!(p::Plot; kw...) = (mergewith!(vcat, p.opt, Dict(kw...)); p)
getplotopt(p::Plot, k, v=nothing) = get(p.opt, k, v)
getplotopt(::Nothing, k, v=nothing) = v

value(p::Plot) = p.obj
Base.getindex(p::Plot) = value(p)
Base.adjoint(p::Plot) = value(p)

Base.showable(m::MIME, p::Plot) = showable(m, p.obj)

Base.show(p::Plot) = show(p.obj)
Base.show(io::IO, p::Plot) = show(io, p.obj)
Base.show(io::IO, m::MIME, p::Plot) = show(io, m, p.obj)
Base.show(io::IO, ::MIME"text/plain", p::Plot) = show(io, "Cropbox.Plot")

Base.display(p::Plot) = display(p.obj)
Base.display(d::AbstractDisplay, p::Plot) = display(d, p.obj)
Base.display(m::MIME, p::Plot) = display(m, p.obj)
Base.display(d::AbstractDisplay, m::MIME, p::Plot) = display(d, m, p.obj)

@nospecialize

extractcolumn(df::DataFrame, n::Symbol) = df[!, n]
extractcolumn(df::DataFrame, n::Expr) = begin
    ts(x) = x isa Symbol ? :(df[!, $(Meta.quot(x))]) : x
    te(x) = @capture(x, f_(a__)) ? :($f($(ts.(a)...))) : x
    #HACK: avoid world age problem for function scope eval
    e = Main.eval(:(df -> @. $(MacroTools.postwalk(te, n))))
    (() -> @eval $e($df))()
end
convertcolumn(c::Vector{ZonedDateTime}) = Dates.DateTime.(c, TimeZones.Local)
convertcolumn(c) = c
extractunit(df::DataFrame, n) = extractunit(extractcolumn(df, n))
extractunit(a) = unittype(a)
extractarray(df::DataFrame, n) = begin
    #HACK: Gadfly doesn't support ZonedDateTime
    convertcolumn(extractcolumn(df, n))
end

findlim(array::Vector{<:Number}) = begin
    a = skipmissing(array)
    l = isempty(a) ? 0 : floor(minimum(a))
    u = isempty(a) ? 0 : ceil(maximum(a))
    #HACK: avoid empty range
    l == u ? (l, l+1) : (l, u)
end
findlim(array) = extrema(skipmissing(array))

label(l, u) = hasunit(u) ? "$l ($u)" : "$l"

detectbackend() = begin
    if isdefined(Main, :IJulia) && Main.IJulia.inited ||
       isdefined(Main, :Juno) && Main.Juno.isactive() ||
       isdefined(Main, :PlutoRunner) ||
       haskey(ENV, "NJS_VERSION")
        :Gadfly
    else
        :UnicodePlots
    end
end

plot(df::DataFrame, x, y; name=nothing, color=nothing, kw...) = plot(df, x, [y]; names=[name], colors=[color], kw...)
plot(df::DataFrame, x, ys::Vector; kw...) = plot!(nothing, df, x, ys; kw...)
plot!(p::Union{Plot,Nothing}, df::DataFrame, x, y; name=nothing, color=nothing, kw...) = plot!(p, df, x, [y]; names=[name], colors=[color], kw...)
plot!(p::Union{Plot,Nothing}, df::DataFrame, x, ys::Vector; xlab=nothing, ylab=nothing, names=nothing, colors=nothing, kw...) = begin
    arr(n) = extractarray(df, n)
    X = arr(x)
    Ys = arr.(ys)

    n = length(Ys)
    xlab = isnothing(xlab) ? x : xlab
    ylab = isnothing(ylab) ? "" : ylab
    names = isnothing(names) ? repeat([nothing], n) : names
    names = [isnothing(n) ? string(y) : n for (y, n) in zip(ys, names)]
    #HACK: support indirect referencing from the given data frame if name is Symbol
    names = [n isa Symbol ? repr(deunitfy(only(unique(df[n]))), context=:compact=>true) : n for n in names]
    colors = isnothing(colors) ? repeat([nothing], n) : colors

    plot!(p, X, Ys; xlab, ylab, names, colors, kw...)
end

plot(X::Vector, Y::Vector; name=nothing, color=nothing, kw...) = plot(X, [Y]; names=isnothing(name) ? nothing : [name], colors=[color], kw...)
plot(X::Vector, Ys::Vector{<:Vector}; kw...) = plot!(nothing, X, Ys; kw...)
plot!(p::Union{Plot,Nothing}, X::Vector, Y::Vector; name=nothing, color=nothing, kw...) = plot!(p, X, [Y]; names=isnothing(name) ? nothing : [name], colors=[color], kw...)
plot!(p::Union{Plot,Nothing}, X::Vector, Ys::Vector{<:Vector};
    kind=:scatter,
    title=nothing,
    xlab=nothing, ylab=nothing,
    legend=nothing, legendpos=nothing,
    names=nothing, colors=nothing,
    xlim=nothing, ylim=nothing,
    xunit=nothing, yunit=nothing,
    aspect=nothing,
    backend=nothing,
) = begin
    u(a) = extractunit(a)
    xunit = getplotopt(p, :xunit, xunit)
    yunit = getplotopt(p, :yunit, yunit)
    isnothing(xunit) && (xunit = u(X))
    isnothing(yunit) && (yunit = promoteunit(u.(Ys)...))

    arr(a, u) = deunitfy(a, u)
    X = arr(X, xunit)
    Ys = arr.(Ys, yunit)

    isnothing(xlim) && (xlim = findlim(X))
    if isnothing(ylim)
        l = findlim.(Ys)
        ylim = (minimum(minimum.(l)), maximum(maximum.(l)))
    end

    n = length(Ys)
    xlab = label(xlab, xunit)
    ylab = label(ylab, yunit)
    if legend === false
        legend = ""
        names = repeat([""], n)
    else
        legend = isnothing(legend) ? "" : string(legend)
        names = isnothing(names) ? string.(1:n) : names
    end
    colors = isnothing(colors) ? repeat([nothing], n) : colors
    title = isnothing(title) ? "" : string(title)

    isnothing(backend) && (backend = detectbackend())
    plot2!(Val(backend), p, X, Ys; kind, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, xunit, yunit, aspect)
end

plot(df::DataFrame, x, y, z;
    kind=:heatmap,
    title=nothing,
    legend=nothing, legendpos=nothing,
    xlab=nothing, ylab=nothing, zlab=nothing,
    xlim=nothing, ylim=nothing, zlim=nothing,
    xunit=nothing, yunit=nothing, zunit=nothing,
    zgap=nothing, zlabgap=nothing,
    aspect=nothing,
    backend=nothing,
) = begin
    u(n) = extractunit(df, n)
    isnothing(xunit) && (xunit = u(x))
    isnothing(yunit) && (yunit = u(y))
    isnothing(zunit) && (zunit = u(z))

    arr(n, u) = deunitfy(extractarray(df, n), u)
    X = arr(x, xunit)
    Y = arr(y, yunit)
    Z = arr(z, zunit)

    isnothing(xlim) && (xlim = findlim(X))
    isnothing(ylim) && (ylim = findlim(Y))
    isnothing(zlim) && (zlim = findlim(Z))

    xlab = label(isnothing(xlab) ? x : xlab, xunit)
    ylab = label(isnothing(ylab) ? y : ylab, yunit)
    zlab = label(isnothing(zlab) ? z : zlab, zunit)
    title = isnothing(title) ? "" : string(title)
    legend = isnothing(legend) ? true : legend

    isnothing(backend) && (backend = detectbackend())
    plot3!(Val(backend), X, Y, Z; kind, title, legend, legendpos, xlab, ylab, zlab, xlim, ylim, zlim, zgap, zlabgap, aspect)
end

plot2!(::Val{:Gadfly}, p::Union{Plot,Nothing}, X, Ys; kind, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, xunit, yunit, aspect) = begin
    n = length(Ys)
    Xs = [X for _ in 1:n]
    kinds = [kind for _ in 1:n]

    if kind == :line
        geoms = [Gadfly.Geom.line]
    elseif kind == :scatter
        geoms = [Gadfly.Geom.point]
    elseif kind == :scatterline
        geoms = [Gadfly.Geom.point, Gadfly.Geom.line]
    else
        error("unrecognized plot kind = $kind")
    end

    #HACK: manual_color_key() expects [] while colorkey() expects nothing
    keypos = isnothing(legendpos) ? [] : legendpos .* [Gadfly.w, Gadfly.h]

    theme = Gadfly.Theme(
        background_color="white",
        plot_padding=[5*Gadfly.mm, 5*Gadfly.mm, 5*Gadfly.mm, 0*Gadfly.mm],
        major_label_font_size=10*Gadfly.pt,
        key_title_font_size=9*Gadfly.pt,
        key_position=isempty(keypos) ? :right : :inside,
        point_size=0.7*Gadfly.mm,
        discrete_highlight_color=_->Gadfly.RGBA(1, 1, 1, 0),
    )

    create_colors(colors; n0=0) = begin
        n = length(colors)
        C = Gadfly.Scale.default_discrete_colors(n0+n)[n0+begin:end]
        f(c::Int, _) = p.opt[:colors][c]
        f(c, _) = parse(Gadfly.Colorant, c)
        f(::Nothing, i) = C[i]
        [f(c, i) for (i, c) in enumerate(colors)]
    end
    colorkey(colors) = begin
        NC = filter(x -> let (n, c) = x; !isempty(n) end, collect(zip(names, colors)))
        if !isempty(NC)
            N, C = first.(NC), last.(NC)
            Gadfly.Guide.manual_color_key(legend, N, C; pos=keypos)
        end
    end
    colorkey!(key, colors) = begin
        k = colorkey(colors)
        if !isnothing(k)
            append!(key.labels, k.labels)
            append!(key.colors, k.colors)
        end
        k
    end
    update_color!(guides, colors) = begin
        #TODO: very hacky approach to append new plots... definitely need a better way
        keys = filter(x -> x isa Gadfly.Guide.ManualDiscreteKey, guides)
        if isempty(keys)
            key = colorkey(colors)
            !isnothing(key) && push!(guides, key)
        else
            key = only(keys)
            colorkey!(key, colors)
        end
    end
    create_layers(colors) = [Gadfly.layer(x=Xs[i], y=Ys[i], geoms..., Gadfly.Theme(theme; default_color=colors[i])) for i in 1:n]

    if isnothing(p)
        guides = [
            Gadfly.Guide.title(title),
            Gadfly.Guide.xlabel(xlab),
            Gadfly.Guide.ylabel(ylab),
        ]
        colors = create_colors(colors)
        update_color!(guides, colors)
        layers = create_layers(colors)
        obj = Gadfly.plot(
            Gadfly.Coord.cartesian(xmin=xlim[1], ymin=ylim[1], xmax=xlim[2], ymax=ylim[2], aspect_ratio=aspect),
            guides...,
            layers...,
            theme,
        )
        p = Plot(obj; Xs, Ys, kinds, colors, title, xlab, ylab, legend, names, xlim, ylim, xunit, yunit, aspect)
    else
        obj = p.obj
        n0 = length(obj.layers)
        colors = create_colors(colors; n0)
        update_color!(obj.guides, colors)
        foreach(l -> Gadfly.push!(obj, l), create_layers(colors))
        for l in create_layers(colors)
            Gadfly.push!(obj, l)
        end
        update!(p; Xs, Ys, kinds, colors, names)
    end
    p
end

plot2!(::Val{:UnicodePlots}, p::Union{Plot,Nothing}, X, Ys; kind, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, xunit, yunit, aspect, width=40, height=15) = begin
    canvas = if get(ENV, "GITHUB_ACTIONS", "false") == "true"
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

    if isnothing(p)
        a = Float64[]
        !isnothing(aspect) && (width = round(Int, aspect * 2height))
        obj = UnicodePlots.Plot(a, a, canvas; title, xlabel=xlab, ylabel=ylab, xlim, ylim, width, height)
        UnicodePlots.annotate!(obj, :r, legend)
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

plot3!(::Val{:Gadfly}, X, Y, Z; kind, title, legend, legendpos, xlab, ylab, zlab, xlim, ylim, zlim, zgap, zlabgap, aspect) = begin
    if kind == :heatmap
        geom = Gadfly.Geom.rectbin
        data = (x=X, y=Y, color=Z)
    elseif kind == :contour
        levels = isnothing(zgap) ? 100 : collect(zlim[1]:zgap:zlim[2])
        geom = Gadfly.Geom.contour(; levels)
        data = (x=X, y=Y, z=Z)
    else
        error("unrecognized plot kind = $kind")
    end

    #HACK: colorkey() expects nothing while manual_color_key() expects []
    keypos = isnothing(legendpos) ? nothing : legendpos .* [Gadfly.w, Gadfly.h]

    theme = Gadfly.Theme(
        background_color="white",
        plot_padding=[5*Gadfly.mm, 5*Gadfly.mm, 5*Gadfly.mm, 0*Gadfly.mm],
        major_label_font_size=10*Gadfly.pt,
        key_title_font_size=9*Gadfly.pt,
        key_position=legend ? isnothing(keypos) ? :right : :inside : :none,
    )

    label(z) = begin
        #TODO: remove redundant creation of Scale
        zmin, zmax = zlim
        zspan = zmax - zmin
        scale = Gadfly.Scale.color_continuous(minvalue=zmin, maxvalue=zmax)
        color = scale.f((z - zmin) / zspan)

        i = findmin(abs.(Z .- z))[2]
        #HACK: ignore lables presumably out of bound
        if i == firstindex(Z) || i == lastindex(Z)
            Gadfly.Guide.annotation(Gadfly.compose(Gadfly.context()))
        else
            x, y = X[i], Y[i]
            Gadfly.Guide.annotation(
                Gadfly.compose(
                    Gadfly.context(),
                    Gadfly.Compose.text(x, y, string(z), Gadfly.hcenter, Gadfly.vcenter),
                    Gadfly.font(theme.minor_label_font),
                    Gadfly.fontsize(theme.minor_label_font_size),
                    Gadfly.fill(color),
                    Gadfly.stroke("white"),
                    Gadfly.linewidth(0.1*Gadfly.pt),
                )
            )
        end
    end
    labels = isnothing(zlabgap) ? () : label.(zlim[1]:zlabgap:zlim[2])

    obj = Gadfly.plot(
        Gadfly.Coord.cartesian(xmin=xlim[1], ymin=ylim[1], xmax=xlim[2], ymax=ylim[2], aspect_ratio=aspect),
        Gadfly.Guide.title(title),
        Gadfly.Guide.xlabel(xlab),
        Gadfly.Guide.ylabel(ylab),
        Gadfly.Guide.colorkey(title=zlab; pos=keypos),
        Gadfly.Scale.color_continuous(minvalue=zlim[1], maxvalue=zlim[2]),
        geom,
        labels...,
        theme;
        data...,
    )
    Plot(obj; X, Y, Z, kind, title, xlab, ylab, zlab, xlim, ylim, zlim, aspect)
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

import Cairo
import ImageMagick
import FileIO
# https://github.com/tshort/SixelTerm.jl
sixel(p::Plot) = begin
    png = IOBuffer()
    # assume Gadfly backend
    #HACK: needs to set emit_on_finish false
    w = Gadfly.Compose.default_graphic_width
    h = Gadfly.Compose.default_graphic_height
    p[] |> Gadfly.PNG(png, w, h, false; dpi=144)
    im = ImageMagick.load(png)
    six = IOBuffer()
    st = FileIO.Stream(FileIO.format"six", six)
    ImageMagick.save(st, im)
    write(stdout, take!(six))
    nothing
end

@specialize

export plot, plot!
