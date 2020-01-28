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
    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    xlab = lab(index) * '\n'
    
    p = UnicodePlots.lineplot(X, Ys[1], name=lab(target[1]), xlabel=xlab, xlim=xlim, ylim=ylim)
    for i in 2:length(Ys)
        UnicodePlots.lineplot!(p, X, Ys[i], name=lab(target[i]))
    end
    p |> display
end
