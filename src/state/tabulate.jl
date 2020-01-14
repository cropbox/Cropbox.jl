struct Tabulate{V} <: State{V}
    value::Dict{Symbol,Dict{Symbol,V}}
    rows::Tuple{Vararg{Symbol}}
    columns::Tuple{Vararg{Symbol}}
end

Tabulate(; unit, rows, columns, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    matrix2dict(m, r, c, V) = Dict(zip(r, [Dict(zip(c, V.(m[i,:]))) for i in 1:size(m, 1)]))
    v = matrix2dict(_value, rows, columns, V)
    Tabulate{V}(v, rows, columns)
end

genvartype(v::VarInfo, ::Val{:Tabulate}; V, _...) = @q Tabulate{$V}

geninit(v::VarInfo, ::Val{:Tabulate}) = geninitpreserve(v)

genupdate(v::VarInfo, ::Val{:Tabulate}, ::MainStep) = genvalue(v)
