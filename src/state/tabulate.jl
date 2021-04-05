using DataStructures: OrderedDict

abstract type Tabulation{V} end

value(t::Tabulation) = getfield(t, :value)
Base.adjoint(t::Tabulation) = value(t)
Base.getproperty(t::Tabulation, k::Symbol) = value(t)[k]
Base.getindex(t::Tabulation, k::Symbol) = getproperty(t, k)
Base.iterate(t::Tabulation) = iterate(value(t))
Base.iterate(t::Tabulation, i) = iterate(value(t), i)

struct TabulationCols{V} <: Tabulation{V}
    value::OrderedDict{Symbol,V}
    TabulationCols{V}(x...) where V = new{V}(OrderedDict(x...))
end

struct TabulationRows{V} <: Tabulation{V}
    value::OrderedDict{Symbol,TabulationCols{V}}
    TabulationRows{V}(x...) where V = new{V}(OrderedDict(x...))
end

import DataFrames: DataFrames, DataFrame
DataFrames.DataFrame(t::TabulationCols) = DataFrame(value(t))
DataFrames.DataFrame(t::TabulationRows; index=true) = begin
    v = value(t)
    I = DataFrame("" => collect(keys(v)))
    C = DataFrame(value.(values(v)))
    index ? [I C] : C
end
Base.Matrix(t::TabulationRows) = Matrix(DataFrame(t; index=false))

Base.show(io::IO, t::TabulationCols) = show(io, DataFrame(t); summary=false, eltypes=false, show_row_number=false, vlines=:none)
Base.show(io::IO, t::TabulationRows) = show(io, DataFrame(t); summary=false, eltypes=false, show_row_number=false, vlines=[1])

tabulation(m, R, C, V) = TabulationRows{V}(R .=> [TabulationCols{V}(zip(C, V.(m[i,:]))) for i in 1:size(m, 1)])

struct Tabulate{V} <: State{V}
    value::TabulationRows{V}
    rows::Tuple{Vararg{Symbol}}
    columns::Tuple{Vararg{Symbol}}
end

Base.getproperty(t::Tabulate, k::Symbol) = t[k]
Base.show(io::IO, t::Tabulate) = show(io, Matrix(value(t)))
Base.show(io::IO, ::MIME"text/plain", t::Tabulate) = show(io, value(t))

Tabulate(; unit, rows, columns=(), _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    columns = isempty(columns) ? rows : columns
    v = tabulation(_value, rows, columns, V)
    Tabulate{V}(v, rows, columns)
end

constructortags(::Val{:Tabulate}) = (:unit, :rows, :columns)

genvartype(v::VarInfo, ::Val{:Tabulate}; V, _...) = @q Tabulate{$V}

geninit(v::VarInfo, ::Val{:Tabulate}) = geninitvalue(v, parameter=true)

genupdate(v::VarInfo, ::Val{:Tabulate}, ::MainStep) = nothing
