import Gadfly

plot2!(::Val{:Gadfly}, p::Union{Plot,Nothing}, X, Ys; kind, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, ycat, xunit, yunit, aspect) = begin
    n = length(Ys)
    Xs = [X for _ in 1:n]
    kinds = [kind for _ in 1:n]

    if kind == :line
        geoms = [Gadfly.Geom.line]
    elseif kind == :scatter
        geoms = [Gadfly.Geom.point]
    elseif kind == :scatterline
        geoms = [Gadfly.Geom.point, Gadfly.Geom.line]
    elseif kind == :step
        geoms = [Gadfly.Geom.step]
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
        NC = filter!(x -> let (n, c) = x; !isempty(n) end, collect(zip(names, colors)))
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
        xmin, xmax = xlim
        ymin, ymax = ylim

        scales = if kind == :step
            [
                Gadfly.Scale.y_discrete(levels=ycat),
                Gadfly.Coord.cartesian(; xmin, xmax, ymin=1, ymax=length(ycat), aspect_ratio=aspect),
            ]
        #HACK: aesthetic adjustment for boolean (flag) plots
        #TODO: remove special adjustment in favor of new step plot
        elseif eltype(ylim) == Bool
            [
                #HACK: ensure correct level order (false low, true high)
                Gadfly.Scale.y_discrete(levels=[false, true]),
                #HACK: shift ylim to avoid clipping true values (discrete false=1, true=2)
                Gadfly.Coord.cartesian(; xmin, xmax, ymin=1, ymax=2, aspect_ratio=aspect),
            ]
        else
            [
                Gadfly.Coord.cartesian(; xmin, xmax, ymin, ymax, aspect_ratio=aspect),
            ]
        end
        guides = [
            Gadfly.Guide.title(title),
            Gadfly.Guide.xlabel(xlab),
            Gadfly.Guide.ylabel(ylab),
        ]
        colors = create_colors(colors)
        update_color!(guides, colors)
        layers = create_layers(colors)
        obj = Gadfly.plot(
            scales...,
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
        for l in create_layers(colors)
            Gadfly.push!(obj, l)
        end
        update!(p; Xs, Ys, kinds, colors, names)
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

    scales = [
        #TODO: fix performance regression with custom system image
        #Gadfly.Scale.x_continuous,
        #Gadfly.Scale.y_continuous,
        Gadfly.Scale.color_continuous(minvalue=zlim[1], maxvalue=zlim[2]),
        Gadfly.Coord.cartesian(xmin=xlim[1], ymin=ylim[1], xmax=xlim[2], ymax=ylim[2], aspect_ratio=aspect),
    ]
    guides = [
        Gadfly.Guide.title(title),
        Gadfly.Guide.xlabel(xlab),
        Gadfly.Guide.ylabel(ylab),
        Gadfly.Guide.colorkey(title=zlab; pos=keypos),
    ]

    obj = Gadfly.plot(
        scales...,
        guides...,
        geom,
        labels...,
        theme;
        data...,
    )
    Plot(obj; X, Y, Z, kind, title, xlab, ylab, zlab, xlim, ylim, zlim, aspect)
end

#HACK: use non-interactive SVG instead of SVGJS
_show(io::IO, m::MIME"text/html", p::Gadfly.Plot) = begin
    w = Gadfly.Compose.default_graphic_width
    h = Gadfly.Compose.default_graphic_height
    Gadfly.SVG(io, w, h, false)(p)
end

import Cairo
import ImageMagick
import FileIO
# https://github.com/tshort/SixelTerm.jl
sixel(p::Gadfly.Plot) = begin
    png = IOBuffer()
    #HACK: needs to set emit_on_finish false
    w = Gadfly.Compose.default_graphic_width
    h = Gadfly.Compose.default_graphic_height
    p |> Gadfly.PNG(png, w, h, false; dpi=144)
    im = ImageMagick.load(png)
    six = IOBuffer()
    st = FileIO.Stream(FileIO.format"six", six)
    ImageMagick.save(st, im)
    write(stdout, take!(six))
    nothing
end
