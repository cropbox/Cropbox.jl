struct Tabulate{V} <: State{V}
    value::Dict{Symbol,Dict{Symbol,V}}
end

Tabulate(; unit, rows, columns, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    matrix2dict(m, r, c, V) = Dict(zip(r, [Dict(zip(c, V.(m[:,i]))) for i in 1:size(m)[2]]))
    v = matrix2dict(_value, rows, columns, V)
    Tabulate{V}(v)
end
