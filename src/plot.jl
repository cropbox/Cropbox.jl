import DataFrames: DataFrame
import UnicodePlots

plot(df::DataFrame, index::Symbol, target::Symbol; kw...) = plot(df, index, [target]; kw...)
plot(df::DataFrame, index::Symbol, target::Vector{Symbol}; kw...) = plot!(nothing, df, index, target; kw...)
plot!(p, df::DataFrame, index::Symbol, target::Symbol; kw...) = plot!(p, df, index, [target]; kw...)
plot!(p, df::DataFrame, index::Symbol, target::Vector{Symbol}; kind=:line, xlabel=nothing, ylabel=nothing) = begin
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

    arr(n::Symbol, u) = deunitfy(df[!, n], u)
    X = arr(index, xu)
    Ys = arr.(target, yu)

    lim(a) = let l = floor(minimum(a)), u = ceil(maximum(a))
        #HACK: avoid empty range
        l == u ? (l, l+1) : (l, u)
    end
    xlim = lim(X)
    ylim = (l = lim.(Ys); (minimum(l)[1], maximum(l)[2]))

    lab(n, l) = let s = string(u(n))
        isempty(s) ? "$l" : "$l ($s)"
    end
    lab(n, ::Nothing) = lab(n, n)
    xlab = lab(index, xlabel)

    if isnothing(p)
        a = Float64[]
        p = UnicodePlots.Plot(a, a, xlabel=xlab, xlim=xlim, ylim=ylim)
    end
    for i in 1:length(Ys)
        plot!(p, X, Ys[i], name=lab(target[i], ylabel))
    end
    p
end
