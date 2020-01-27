import DataFrames: DataFrame
import UnicodePlots

plot(df::DataFrame, index::Symbol, target::Symbol) = plot(df, index, [target])
plot(df::DataFrame, index::Symbol, target::Vector{Symbol}) = begin
    u(n) = unit(eltype(df[!, n]))
    xu = u(index)
    yu = Unitful.promote_unit(u.(target)...)
    
    arr(n::Symbol, u) = deunitfy(df[!, n], u)
    X = arr(index, xu)
    Ys = arr.(target, yu)
    
    lim(a) = (floor(minimum(a)), ceil(maximum(a)))
    xlim = lim(X)
    ylim = (l = lim.(Ys); (minimum(l)[1], maximum(l)[2]))
    
    lab(n) = (s = string(u(n)); isempty(s) ? "$n" : "$n ($s)")
    xlab = lab(index)
    
    p = UnicodePlots.scatterplot(X, Ys[1], name=lab(target[1]), xlabel=xlab, xlim=xlim, ylim=ylim)
    for i in 2:length(Ys)
        UnicodePlots.scatterplot!(p, X, Ys[i], name=lab(target[i]))
    end
    p
end
