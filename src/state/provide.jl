using DataFrames: DataFrame
import CSV

mutable struct Provide{V} <: State{V}
    value::V
end

Provide(; index, time, step, autounit, _value, _type, _...) = begin
    i = value(index)
    t = value(time)
    Δt = value(step)
    df = DataFrame(_value isa String ? CSV.File(_value) : _value)
    df = autounit ? unitfy(df) : df
    v = filter(r -> r[i] >= t && iszero(typeof(Δt)(r[i] - t) % Δt), df)
    v[1, i] != t && error("incompatible index for initial time = $t\n$v")
    !all(isequal(Δt), diff(v[!, i])) && error("incompatible index for time step = $Δt\n$v")
    V = _type
    Provide{V}(v)
end

constructortags(::Val{:Provide}) = (:index, :time, :step, :autounit)

updatetags!(d, ::Val{:Provide}; _...) = begin
    !haskey(d, :index) && (d[:index] = QuoteNode(:index))
    !haskey(d, :time) && (d[:time] = :(context.clock.time))
    !haskey(d, :step) && (d[:step] = :(context.clock.step))
    !haskey(d, :autounit) && (d[:autounit] = true)
end

genvartype(v::VarInfo, ::Val{:Provide}; V, _...) = @q Provide{$V}

geninit(v::VarInfo, ::Val{:Provide}) = istag(v, :parameter) ? genparameter(v) : genbody(v)

genupdate(v::VarInfo, ::Val{:Provide}, ::MainStep) = nothing
