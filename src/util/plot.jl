import DataFrames: DataFrame
import UnicodePlots

plot(df::DataFrame, index::Symbol, target::Symbol; ylabel=nothing, kw...) = plot(df, index, [target]; ylabel=[ylabel], kw...)
plot(df::DataFrame, index::Symbol, target::Vector{Symbol}; kw...) = plot!(nothing, df, index, target; kw...)
plot!(p, df::DataFrame, index::Symbol, target::Symbol; ylabel=nothing, kw...) = plot!(p, df, index, [target]; ylabel=[ylabel], kw...)
plot!(p, df::DataFrame, index::Symbol, target::Vector{Symbol}; kind=:line, xlabel=nothing, ylabel=nothing, xlim=nothing, ylim=nothing) = begin
    if kind == :line
        plot = UnicodePlots.lineplot
        plot! = UnicodePlots.lineplot!
    elseif kind == :scatter
        plot = UnicodePlots.scatterplot
        plot! = UnicodePlots.scatterplot!
    else
        error("unrecognized plot kind = $kind")
    end

    u(n) = unit(eltype(df[!, n]))
    xu = u(index)
    yu = Unitful.promote_unit(u.(target)...)

    arr(n::Symbol, u) = deunitfy.(df[!, n], u)
    X = arr(index, xu)
    Ys = arr.(target, yu)
    n = length(Ys)

    lim(a) = let l = floor(minimum(a)), u = ceil(maximum(a))
        #HACK: avoid empty range
        l == u ? (l, l+1) : (l, u)
    end
    isnothing(xlim) && (xlim = lim(X))
    if isnothing(ylim)
        l = lim.(Ys)
        ylim = (minimum(l)[1], maximum(l)[2])
    end

    lab(n, l) = let s = string(u(n))
        isempty(s) ? "$l" : "$l ($s)"
    end
    lab(n, ::Nothing) = lab(n, n)
    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    xlab = lab(index, xlabel) * '\n'
    ylabs = isnothing(ylabel) ? repeat([nothing], n) : ylabel

    if isnothing(p)
        a = Float64[]
        p = UnicodePlots.Plot(a, a, xlabel=xlab, xlim=xlim, ylim=ylim)
    end
    for i in 1:n
        plot!(p, X, Ys[i], name=lab(target[i], ylabs[i]))
    end
    p
end
