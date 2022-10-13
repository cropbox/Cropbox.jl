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
#HACK: custom hook for intercepting 3-args show() from each backend (i.e. Gadfly)
Base.show(io::IO, m::MIME, p::Plot) = _show(io, m, p.obj)
_show(io::IO, m::MIME, o) = show(io, m, o)
Base.show(io::IO, ::MIME"text/plain", p::P) where {P<:Plot} = show(io, "<$P>")

Base.display(p::Plot) = display(p.obj)
Base.display(d::AbstractDisplay, p::Plot) = display(d, p.obj)
Base.display(m::MIME, p::Plot) = display(m, p.obj)
Base.display(d::AbstractDisplay, m::MIME, p::Plot) = display(d, m, p.obj)

extractcolumn(df::DataFrame, n::Symbol) = df[!, n]
extractcolumn(df::DataFrame, n::String) = extractcolumn(df, Symbol(n))
extractcolumn(df::DataFrame, n::Expr) = begin
    ts(x) = x isa Symbol ? :(df[!, $(Meta.quot(x))]) : x
    te(x) = @capture(x, f_(a__)) ? :($f($(ts.(a)...))) : x
    #HACK: avoid world age problem for function scope eval
    e = Main.eval(:(df -> @. $(MacroTools.postwalk(te, n))))
    (() -> @eval $e($df))()
end
convertcolumn(c::Vector{ZonedDateTime}) = Dates.DateTime.(c)
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
    l == u ? (l-1, l+1) : (l, u)
end
findlim(array) = extrema(skipmissing(array))

label(l, u) = hasunit(u) ? "$l ($u)" : "$l"

detectbackend() = begin
    if isdefined(Main, :IJulia) && Main.IJulia.inited ||
       isdefined(Main, :Juno) && Main.Juno.isactive() ||
       isdefined(Main, :VSCodeServer) ||
       isdefined(Main, :PlutoRunner) ||
       isdefined(Main, :Documenter) && any(t -> startswith(string(t.func), "#makedocs#"), stacktrace()) ||
       haskey(ENV, "NJS_VERSION")
        :Gadfly
    else
        :UnicodePlots
    end
end

"""
    plot(df::DataFrame, x, y; <keyword arguments>) -> Plot
    plot(X::Vector, Y::Vector; <keyword arguments>) -> Plot
    plot(df::DataFrame, x, y, z; <keyword arguments>) -> Plot

Plot a graph from provided data source. The type of graph is selected based on arguments.

See also: [`plot!`](@ref), [`visualize`](@ref)
"""
plot(df::DataFrame, x, y; name=nothing, color=nothing, kw...) = plot(df, x, [y]; names=[name], colors=[color], kw...)
plot(df::DataFrame, x, ys::Vector; kw...) = plot!(nothing, df, x, ys; kw...)
"""
    plot!(p, <arguments>; <keyword arguments>) -> Plot

Update an existing `Plot` object `p` by appending a new graph made with `plot`.

See also: [`plot`](@ref)

# Arguments
- `p::Union{Plot,Nothing}`: plot object to be updated; `nothing` creates a new plot.
"""
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
    names = [n isa Symbol ? repr(deunitfy(only(unique(df[!, n]))), context=:compact=>true) : n for n in names]
    colors = isnothing(colors) ? repeat([nothing], n) : colors

    plot!(p, X, Ys; xlab, ylab, names, colors, kw...)
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
plot!(p::Union{Plot,Nothing}, X::Vector; kind, xlim=nothing, ylim=nothing, kw...) = begin
    xlim = getplotopt(p, :xlim, xlim)
    ylim = getplotopt(p, :ylim, ylim)
    if kind == :hline
        isnothing(xlim) && error("hline requires `xlim`: $V")
        ylim = isnothing(ylim) ? findlim(X) : ylim
    elseif kind == :vline
        isnothing(ylim) && error("vline requires `ylim`: $V")
        xlim = isnothing(xlim) ? findlim(X) : xlim
    else
        error("unsupported `kind` for single value plot: $kind")
    end
    plot!(p, X, []; kind, xlim, ylim, kw...)
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
    ycat=nothing,
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

    if kind == :step && isnothing(ycat)
        if all(isequal(Bool), eltype.(Ys))
            ycat = [false, true]
        else
            l = unique.(Ys)
            ycat = unique(Iterators.flatten(l))
        end
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
    plot2!(Val(backend), p, X, Ys; kind, title, xlab, ylab, legend, legendpos, names, colors, xlim, ylim, ycat, xunit, yunit, aspect)
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

sixel(p::Plot) = sixel(p[])
sixel(::P) where P = error("sixel not supported: $P")

include("plot/UnicodePlots.jl")
include("plot/Gadfly.jl")

export plot, plot!
