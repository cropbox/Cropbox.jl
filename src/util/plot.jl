using DataFrames: DataFrame
using MacroTools: @capture
import Unitful

struct Plot{T}
    obj::T
    opt::Dict{Symbol,Any}
    Plot(obj; kw...) = new{typeof(obj)}(obj, Dict(kw...))
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
Base.show(io::IO, ::MIME"text/plain", p::P) where {P<:Plot} = show(io, "<$P>")

Base.display(p::Plot) = display(p.obj)
Base.display(d::AbstractDisplay, p::Plot) = display(d, p.obj)
Base.display(m::MIME, p::Plot) = display(m, p.obj)
Base.display(d::AbstractDisplay, m::MIME, p::Plot) = display(d, m, p.obj)

"""
    Cropbox.writeimage(name::AbstractString, p::Plot; format=nothing, kwargs...)

Save a Makie visualization as PNG, SVG, or PDF and return the output filename.
The filename extension selects the format; `format` appends it when needed.
Additional keywords are passed to CairoMakie's `save`, e.g. `px_per_unit = 2`.
For terminal plots, create the visualization with `backend = :Makie` first.
"""
writeimage(::AbstractString, p::Plot; kw...) =
    throw(ArgumentError("image export is not supported for $(detectbackend(p)); use backend = :Makie"))

extractcolumn(df::AbstractDataFrame, n::Symbol) = df[!, n]
extractcolumn(df::AbstractDataFrame, n::String) = extractcolumn(df, Symbol(n))
extractcolumn(df::AbstractDataFrame, n::Expr) = begin
    ts(x) = x isa Symbol ? :(df[!, $(Meta.quot(x))]) : x
    te(x) = @capture(x, f_(a__)) ? :($f($(ts.(a)...))) : x
    #HACK: avoid world age problem for function scope eval
    e = Main.eval(:(df -> @. $(MacroTools.postwalk(te, n))))
    Base.invokelatest(e, df)
end
convertcolumn(c::AbstractVector{ZonedDateTime}) = Dates.DateTime.(c)
convertcolumn(c) = c
extractunit(df::AbstractDataFrame, n) = extractunit(extractcolumn(df, n))
extractunit(a) = unittype(a)
extractarray(df::AbstractDataFrame, n) = collect(convertcolumn(extractcolumn(df, n)))

findlim(array::Vector{<:Union{Number,Missing}}) = begin
    a = skipmissing(array)
    isempty(a) && return (-1, 1)
    a = Iterators.filter(isfinite, a)
    isempty(a) && throw(ArgumentError("cannot infer plot limits without finite values; specify explicit limits"))
    l, u = floor(minimum(a)), ceil(maximum(a))
    #HACK: avoid empty range
    l == u ? (l-1, l+1) : (l, u)
end
findlim(array) = begin
    l, u = extrema(skipmissing(array))
    l == u && l isa Union{Dates.Date,Dates.DateTime} ? (l - Dates.Day(1), u + Dates.Day(1)) : (l, u)
end

makegrid(X, Y, Z) = begin
    length(unique(zip(X, Y))) == length(Z) || throw(ArgumentError("grid coordinates must be unique"))
    x, y = sort(unique(X)), sort(unique(Y))
    M = fill(NaN, length(x), length(y))
    for (xx, yy, z) in zip(X, Y, Z)
        M[searchsortedfirst(x, xx), searchsortedfirst(y, yy)] = coalesce(z, NaN)
    end
    x, y, M
end

groupplotlimits(p, data, x, ys;
    backend = nothing, xunit = nothing, yunit = nothing, xlim = nothing, ylim = nothing,
    kind = nothing, ycat = nothing, kw...
) = begin
    # the terminal canvas needs the complete range before drawing.
    (!isnothing(p) || plotbackend(p, backend) != :UnicodePlots) && return (;)
    df = data isa AbstractDataFrame ? data : reduce(vcat, data)
    X, Ys = extractarray(df, x), [extractarray(df, y) for y in ys]
    isnothing(xunit) && (xunit = extractunit(X))
    isnothing(yunit) && (yunit = promoteunit(extractunit.(Ys)...))
    Ys = deunitfy.(Ys, yunit)
    isnothing(xlim) && (xlim = findlim(deunitfy(X, xunit)))
    isnothing(ylim) && (ylim = findlim(vcat(Ys...)))
    if kind == :step
        isnothing(ycat) && (ycat = all(isequal(Bool), eltype.(Ys)) ? [false, true] : unique(Iterators.flatten(Ys)))
        return (; xlim, ylim, ycat)
    end
    (; xlim, ylim)
end

label(l, u) = begin
    l = isnothing(l) ? "" : l
    hasunit(u) ? "$l ($u)" : "$l"
end

preparegroups(df, ys; group, names = nothing, legend = nothing) = begin
    groups = DataFrames.groupby(df, group; sort = false)
    isempty(groups) && throw(ArgumentError("no groups to visualize"))
    n = length(ys)
    labels = [join((v isa AbstractString ? v : repr(deunitfy(v), context = :compact => true) for v in Tuple(k)), ", ") for k in keys(groups)]
    isnothing(names) && (names = [n == 1 ? l : "$l: $y" for l in labels for y in ys])
    isnothing(legend) && (legend = join([label(k, extractunit(df, k)) for k in DataFrames.groupcols(groups)], ", "))
    groups, names, legend
end

checklengths(n; kw...) = begin
    for (k, v) in kw
        isnothing(v) || length(v) == n || throw(ArgumentError("$k must contain $n entries (one per series)"))
    end
end

detectbackend() = begin
    if isdefined(Main, :IJulia) && Main.IJulia.inited ||
       isdefined(Main, :Juno) && Main.Juno.isactive() ||
       isdefined(Main, :VSCodeServer) ||
       isdefined(Main, :PlutoRunner) ||
       isdefined(Main, :Documenter) && any(t -> startswith(string(t.func), "#makedocs#"), stacktrace()) ||
       haskey(ENV, "NJS_VERSION")
        :Makie
    else
        :UnicodePlots
    end
end
detectbackend(::Nothing) = detectbackend()

plotbackend(p, backend) = begin
    backend == :Gadfly && throw(ArgumentError("Gadfly is no longer supported; use backend = :Makie"))
    b = detectbackend(p)
    !isnothing(p) && !isnothing(backend) && backend != b &&
        throw(ArgumentError("cannot append $backend output to a $b visualization"))
    isnothing(backend) ? b : backend
end

"""
    plot(df::DataFrame, x, y; <keyword arguments>) -> Plot
    plot(X::Vector, Y::Vector; <keyword arguments>) -> Plot
    plot(df::DataFrame, x, y, z; <keyword arguments>) -> Plot

Plot a graph from provided data source. The type of graph is selected based on arguments.

See also: [`plot!`](@ref), [`visualize`](@ref)
"""
plot(df::AbstractDataFrame, x, y; name=nothing, color=nothing, kw...) = plot(df, x, [y]; names=isnothing(name) ? nothing : [name], colors=isnothing(color) ? nothing : [color], kw...)
plot(df::AbstractDataFrame, x, ys::Vector; kw...) = plot!(nothing, df, x, ys; kw...)
"""
    plot!(p, <arguments>; <keyword arguments>) -> Plot

Update an existing `Plot` object `p` by appending a new graph made with `plot`.

See also: [`plot`](@ref)

# Arguments
- `p::Union{Plot,Nothing}`: plot object to be updated; `nothing` creates a new plot.
"""
plot!(p::Union{Plot,Nothing}, df::AbstractDataFrame, x, y; name=nothing, color=nothing, kw...) = plot!(p, df, x, [y]; names=isnothing(name) ? nothing : [name], colors=isnothing(color) ? nothing : [color], kw...)
plot!(p::Union{Plot,Nothing}, df::AbstractDataFrame, x, ys::Vector;
    group = nothing, xlab = nothing, ylab = nothing, legend = nothing, names = nothing, colors = nothing, kw...
) = begin
    if !isnothing(group)
        groups, names, legend = preparegroups(df, ys; group, names, legend)
        n = length(ys)
        count = length(groups) * n
        names isa Symbol && (names = fill(names, count))
        checklengths(count; names, colors)
        isnothing(colors) && (colors = fill(nothing, count))
        limits = groupplotlimits(p, df, x, ys; kw...)
        for (i, d) in enumerate(groups)
            ii = (i - 1) * n + 1:i * n
            p = plot!(p, d, x, ys; xlab, ylab, legend, names = names[ii], colors = colors[ii], kw..., limits...)
        end
        return p
    end
    arr(n) = extractarray(df, n)
    X = arr(x)
    Ys = arr.(ys)

    n = length(Ys)
    checklengths(n; names, colors)
    xlab = isnothing(xlab) ? x : xlab
    ylab = isnothing(ylab) ? "" : ylab
    names = isnothing(names) ? repeat([nothing], n) : names
    names = [isnothing(n) ? string(y) : n for (y, n) in zip(ys, names)]
    #HACK: support indirect referencing from the given data frame if name is Symbol
    names = [n isa Symbol ? repr(deunitfy(only(unique(df[!, n]))), context=:compact=>true) : n for n in names]
    colors = isnothing(colors) ? repeat([nothing], n) : colors

    plot!(p, X, Ys; xlab, ylab, legend, names, colors, kw...)
end

"""
    plot(v::Number; kind, <keyword arguments>) -> Plot
    plot(V::Vector; kind, <keyword arguments>) -> Plot

Plot a graph of horizontal/vertical lines depending on `kind`, which can be either `:hline` or `:vline`.
An initial plotting of `hline` requires `xlim` and `vline` requires `ylim`, respectively.

See also: [`plot!`](@ref), [`visualize`](@ref)
"""
plot(v::Number; kw...) = plot([v]; kw...)
plot!(p::Union{Plot,Nothing}, v::Number; kw...) = plot!(p, [v]; kw...)
plot(V::Vector; kw...) = plot!(nothing, V; kw...)
plot!(p::Union{Plot,Nothing}, X::Vector;
    kind, xlim = nothing, ylim = nothing, xunit = nothing, yunit = nothing, kw...
) = begin
    xlim = getplotopt(p, :xlim, xlim)
    ylim = getplotopt(p, :ylim, ylim)
    xunit = getplotopt(p, :xunit, xunit)
    yunit = getplotopt(p, :yunit, yunit)
    if kind == :hline
        isnothing(p) && isnothing(xlim) && throw(ArgumentError("hline requires `xlim`"))
        isnothing(yunit) && (yunit = extractunit(X))
        isnothing(p) && isnothing(ylim) && (ylim = findlim(deunitfy(X, yunit)))
    elseif kind == :vline
        isnothing(p) && isnothing(ylim) && throw(ArgumentError("vline requires `ylim`"))
        isnothing(xunit) && (xunit = extractunit(X))
        isnothing(p) && isnothing(xlim) && (xlim = findlim(deunitfy(X, xunit)))
    else
        error("unsupported `kind` for single value plot: $kind")
    end
    plot!(p, X, []; kind, xlim, ylim, xunit, yunit, kw...)
end

plot(X::Vector, Y::Vector; name=nothing, color=nothing, kw...) = plot(X, [Y]; names=isnothing(name) ? nothing : [name], colors=[color], kw...)
plot(X::Vector, Ys::Vector{<:Vector}; kw...) = plot!(nothing, X, Ys; kw...)
plot!(p::Union{Plot,Nothing}, X::Vector, Y::Vector; name=nothing, color=nothing, kw...) = plot!(p, X, [Y]; names=isnothing(name) ? nothing : [name], colors=[color], kw...)
plot!(p::Union{Plot,Nothing}, X::Vector, Ys::Vector{<:Vector};
    kind=:scatter,
    linestyle=:solid,
    title=nothing,
    xlab=nothing, ylab=nothing,
    legend=nothing, legendpos=nothing,
    names=nothing, colors=nothing,
    xlim=nothing, ylim=nothing,
    ycat=nothing,
    xunit=nothing, yunit=nothing,
    aspect=nothing,
    backend=nothing,
) = begin
    n = length(Ys)
    checklengths(n; names, colors)
    all(s -> s in (:solid, :dash, :dot, :dashdot, :dashdotdot), linestyle isa AbstractVector ? linestyle : (linestyle,)) ||
        throw(ArgumentError("unsupported line style: $linestyle"))
    linestyle isa AbstractVector && length(linestyle) != length(Ys) &&
        throw(ArgumentError("line styles must contain one entry per y variable"))
    backend = plotbackend(p, backend)
    isnothing(legendpos) && (legendpos = getplotopt(p, :legendpos))
    u(a) = extractunit(a)
    xunit = getplotopt(p, :xunit, xunit)
    yunit = getplotopt(p, :yunit, yunit)
    isnothing(xunit) && kind != :hline && (xunit = u(X))
    isnothing(yunit) && (yunit = kind == :hline ? u(X) : promoteunit(u.(Ys)...))

    arr(a, u) = deunitfy(a, u)
    X = arr(X, kind == :hline ? yunit : xunit)
    Ys = arr.(Ys, yunit)

    isnothing(xlim) && (xlim = getplotopt(p, :xlim))
    isnothing(ylim) && (ylim = getplotopt(p, :ylim))

    if kind == :step && isnothing(ycat)
        if all(isequal(Bool), eltype.(Ys))
            ycat = [false, true]
        else
            l = unique.(Ys)
            ycat = unique(Iterators.flatten(l))
        end
    end

    xlab = label(xlab, xunit)
    ylab = label(ylab, yunit)
    if legend === false
        legend = ""
        names = repeat([""], n)
    else
        legend = isnothing(legend) ? "" : string(legend)
        n0 = length(getplotopt(p, :Ys, []))
        names = isnothing(names) ? "#" .* string.(n0+1:n0+n) : names
    end
    colors = isnothing(colors) ? repeat([nothing], n) : colors
    title = isnothing(title) ? "" : string(title)

    plot2!(Val(backend), p, X, Ys; kind, linestyle, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, ycat, xunit, yunit, aspect)
end

plot(df::AbstractDataFrame, x, y, z;
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

    backend = plotbackend(nothing, backend)
    plot3!(Val(backend), X, Y, Z; kind, title, legend, legendpos, xlab, ylab, zlab, xlim, ylim, zlim, xunit, yunit, zunit, zgap, zlabgap, aspect)
end

include("plot/UnicodePlots.jl")
include("plot/Makie.jl")

export plot, plot!
