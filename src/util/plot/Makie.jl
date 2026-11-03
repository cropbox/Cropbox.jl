import Makie
import CairoMakie
using Dates: Date, DateTime, Time, year, month, day

classic_ticklabels(values) = Makie.get_ticklabels(Makie.automatic, values)
classic_ticklabels(values::AbstractVector{<:Union{Date,DateTime}}) = begin
    labels = String[]
    for (i, t) in enumerate(values)
        prev = i == 1 ? nothing : values[i - 1]
        format = isnothing(prev) || year(t) != year(prev) ? "u d, yyyy" :
            Date(t) == Date(prev) ? "HH:MM:SS" :
            month(t) != month(prev) ? (day(t) == 1 ? "u" : "u d") : "d"
        if t isa DateTime && Time(t) != Time(0) && format != "HH:MM:SS"
            format *= "\nHH:MM:SS"
        end
        push!(labels, Dates.format(t, format))
    end
    labels
end

theme_classic() = begin
    # Makie 0.24 only searches its fallback list, not system fonts, for missing glyphs.
    lock(Makie.FONT_LOCK) do
        font = Makie.to_font(joinpath(pkgdir(@__MODULE__), "assets", "fonts", "NotoSansCJKkr-Regular.otf"))
        fallbacks = Makie.alternativefonts()
        font in fallbacks || push!(fallbacks, font)
    end
    major, minor = "#564A55", "#6C606B"
    fonts = (; regular = Makie.assetpath("fonts", "NotoSans-Regular.ttf"), bold = Makie.assetpath("fonts", "NotoSans-Bold.ttf"))
    # Gadfly's categorical palette, expressed using Colors through Makie.
    colors = Makie.distinguishable_colors(32, [Makie.LCHab(70, 60, 240)];
        transform = c -> Makie.deuteranopic(c, 0.5),
        lchoices = [65, 70, 75, 80], cchoices = [0, 50, 60, 70], hchoices = range(0, 330; length = 24))
    colormap = [Makie.LCHab(min(80, 100 - 70abs(2r - 1)^1.5), max(10, 40abs(2r - 1)), (1-r)*260 + r*10)
        for r in range(0, 1; length = 256)]
    Makie.Theme(;
        size = (480, 320), figure_padding = (14, 32, 7, 14),
        fontsize = 12, fonts, textcolor = major,
        palette = (; color = colors), colormap,
        linewidth = 0.85, markersize = 4,
        Scatter = (; strokewidth = 0), ScatterLines = (; strokewidth = 0),
        Axis = (;
            backgroundcolor = :white,
            titlefont = :regular, titlesize = 12, titlecolor = major, titlegap = 12,
            xlabelsize = 12, ylabelsize = 12,
            xlabelcolor = major, ylabelcolor = major,
            xlabelpadding = 12, ylabelpadding = 12,
            xtickformat = classic_ticklabels, ytickformat = classic_ticklabels,
            xticklabelsize = 10, yticklabelsize = 10,
            xticklabelcolor = minor, yticklabelcolor = minor,
            xticklabelpad = 5, yticklabelpad = 5,
            xticksvisible = false, yticksvisible = false,
            xgridcolor = "#D0D0E0", ygridcolor = "#D0D0E0",
            xgridwidth = 0.57, ygridwidth = 0.57,
            xgridstyle = Makie.Linestyle([0, 2.5, 5]), ygridstyle = Makie.Linestyle([0, 2.5, 5]),
            topspinevisible = false, rightspinevisible = false, leftspinevisible = false, bottomspinevisible = false),
        Legend = (;
            framevisible = false,
            padding = (0, 0, 0, 0),
            titlefont = :regular, titlesize = 11, titlecolor = "#362A35",
            titlehalign = :left, titlegap = 4,
            labelsize = 10, labelcolor = "#4C404B",
            patchsize = (12, 8), patchlabelgap = 4, rowgap = 1),
        Colorbar = (;
            width = 7, height = 90, tellheight = false,
            labelsize = 11, labelcolor = major,
            ticklabelsize = 10, ticklabelcolor = minor,
            ticksvisible = false, spinewidth = 0,
            topspinevisible = false, rightspinevisible = false, leftspinevisible = false, bottomspinevisible = false))
end

detectbackend(::Plot{<:Makie.Figure}) = :Makie

writeimage(name::AbstractString, p::Plot{<:Makie.Figure}; format = nothing, kw...) = begin
    name, _ = imagefile(name, format)
    CairoMakie.save(name, p[]; backend = CairoMakie, kw...)
    name
end

figure(; title, xlab, ylab, aspect) = Makie.with_theme(theme_classic()) do
    f = Makie.Figure()
    aspect = isnothing(aspect) ? nothing : Makie.AxisAspect(aspect)
    ax = Makie.Axis(f[1, 1]; title, xlabel = xlab, ylabel = ylab, aspect)
    f, ax
end

# Gadfly places a key's left edge and vertical centre relative to the panel.
keybox(ax, pos) = Makie.lift(ax.scene.viewport) do r
    Makie.Rect2f(r.origin .+ (pos[1] * r.widths[1], -pos[2] * r.widths[2]), r.widths)
end

legend!(p) = begin
    old = getplotopt(p, :key)
    isnothing(old) || Makie.delete!(old)
    entries = p.opt[:entries]
    isempty(entries) && return
    title = isempty(p.opt[:legend]) ? nothing : p.opt[:legend]
    pos = p.opt[:legendpos]
    p.opt[:key] = if isnothing(pos)
        Makie.Legend(p.obj[1, 2], entries, p.opt[:labels], title)
    elseif pos isa Symbol
        Makie.axislegend(p.opt[:axis], entries, p.opt[:labels], title; position = pos)
    else
        Makie.Legend(p.obj, entries, p.opt[:labels], title;
            bbox = keybox(p.opt[:axis], pos), halign = :left, valign = :center, margin = (0, 0, 0, 0),
            tellwidth = false, tellheight = false)
    end
end

plot2!(::Val{:Makie}, p::Union{Plot,Nothing}, X, Ys;
    kind, linestyle, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, ycat, xunit, yunit, aspect,
) = begin
    kind in (:line, :scatter, :scatterline, :step, :hline, :vline) ||
        throw(ArgumentError("unrecognized plot kind = $kind"))
    if isnothing(p)
        obj, axis = figure(; title, xlab, ylab, aspect)
        p = Plot(obj;
            axis, Xs = [], Ys = [], kinds = [], colors = [], names = [], entries = [], labels = [],
            title, xlab, ylab, legend, legendpos,
            xlim, ylim, ycat, xunit, yunit, aspect)
        if !isnothing(ycat)
            axis.ytickformat = Makie.automatic
        end
    end
    ax = p.opt[:axis]
    palette = Makie.theme(ax.scene, :palette)[:color][]
    n0 = length(p.opt[:colors])
    n = kind in (:hline, :vline) ? 1 : length(Ys)
    cats = p.opt[:ycat]
    if !isnothing(cats)
        !isnothing(ycat) && (cats = p.opt[:ycat] = union(cats, ycat))
        ax.yticks = (1:length(cats), string.(cats))
    end
    for i in 1:n
        c = isempty(colors) ? nothing : colors[i]
        color = isnothing(c) ? palette[mod1(n0 + i, length(palette))] :
            c isa Integer ? p.opt[:colors][c] : c
        name = isempty(names) ? "" : names[i]
        Y = kind in (:hline, :vline) ? [] : Ys[i]
        if kind in (:hline, :vline)
            draw! = kind == :hline ? Makie.hlines! : Makie.vlines!
            obj = draw!(ax, X; color, linestyle)
        else
            y = isnothing(cats) ? coalesce.(Y, NaN) : Int.(indexin(Y, cats))
            order = kind == :scatter ? eachindex(X) : sortperm(X)
            x, y = X[order], y[order]
            obj = if kind == :scatter
                Makie.scatter!(ax, x, y; color)
            elseif kind == :step
                Makie.stairs!(ax, x, y; color, linestyle, step = :post)
            elseif kind == :scatterline
                Makie.scatterlines!(ax, x, y; color, linestyle)
            else
                Makie.lines!(ax, x, y; color, linestyle)
            end
        end
        if !isempty(name)
            push!(p.opt[:entries], obj)
            push!(p.opt[:labels], name)
        end
        update!(p; Xs = [X], Ys = [Y], kinds = [kind], colors = [color], names = [name])
    end
    Makie.xlims!(ax, p.opt[:xlim]...)
    Makie.ylims!(ax, isnothing(cats) ? p.opt[:ylim] : (0.8, length(cats) + 0.2))
    any(!isempty, names) && legend!(p)
    p
end

plot3!(::Val{:Makie}, X, Y, Z;
    kind, title, legend, legendpos, xlab, ylab, zlab, xlim, ylim, zlim, xunit, yunit, zunit, zgap, zlabgap, aspect,
) = begin
    kind in (:heatmap, :contour) || throw(ArgumentError("unrecognized plot kind = $kind"))
    length(unique(zip(X, Y))) == length(Z) || throw(ArgumentError("grid coordinates must be unique"))
    x, y = sort(unique(X)), sort(unique(Y))
    M = fill(NaN, length(x), length(y))
    for (xx, yy, z) in zip(X, Y, Z)
        M[searchsortedfirst(x, xx), searchsortedfirst(y, yy)] = coalesce(z, NaN)
    end
    obj, axis = figure(; title, xlab, ylab, aspect)
    layer = if kind == :heatmap
        Makie.heatmap!(axis, x, y, M; colorrange = zlim)
    else
        levels = isnothing(zgap) ? 100 : collect(zlim[1]:zgap:zlim[2])
        Makie.contour!(axis, x, y, M; levels, colorrange = zlim)
    end
    if kind == :contour && !isnothing(zlabgap)
        # Makie 0.24 can compute a NaN rotation for a single label with an identity tuple.
        tf = Makie.transform_func(axis.scene)
        tf == (identity, identity) && (tf = identity)
        transformation = Makie.Transformation(axis.scene; transform_func = tf)
        Makie.contour!(axis, x, y, M;
            levels = collect(zlim[1]:zlabgap:zlim[2]), colorrange = zlim,
            labels = true, labelcolor = axis.xticklabelcolor[], labelsize = axis.xticklabelsize[],
            linewidth = 0, transformation)
    end
    if legend
        if isnothing(legendpos)
            Makie.Colorbar(obj[1, 2], layer; label = zlab)
        else
            Makie.Colorbar(obj, layer;
                label = zlab,
                bbox = keybox(axis, legendpos), halign = :left, valign = :center,
                tellwidth = false, tellheight = false)
        end
    end
    Makie.xlims!(axis, xlim...)
    Makie.ylims!(axis, ylim...)
    Plot(obj;
        axis, X, Y, Z, kind,
        title, legend, legendpos, xlab, ylab, zlab,
        xlim, ylim, zlim, xunit, yunit, zunit, aspect)
end

plottext!(::Val{:Makie}, p, x, y, text; color, align) = begin
    ax = p.opt[:axis]
    color = isnothing(color) ? ax.xticklabelcolor[] : color
    Makie.text!(ax, x, y;
        text, align = (align, :center),
        color, fontsize = ax.xticklabelsize[], font = ax.xticklabelfont[])
    p
end
