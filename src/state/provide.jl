using DataFrames: DataFrame
import CSV

mutable struct Provide{V} <: State{V}
    value::V
end

Provide(; index, init, step, autounit, _value, _type, _...) = begin
    i = value(index)
    t = value(init)
    Δt = value(step)
    df = DataFrame(_value isa String ? CSV.File(_value) : _value)
    df = autounit ? unitfy(df) : df
    if t isa Number && Δt isa Number && typeof(Δt) <: Union{Rational,Quantity{<:Rational}}
        N = Δt isa Quantity ? typeof(Unitful.ustrip(Δt)) : typeof(Δt)
        t = exactify(N, t)
        c = df[!, i]
        if any(hasfloatvalue, c)
            @warn "floating-point time-series index converted to exact rational values" index=i
        end
        df[!, i] = [exactify(N, x; warn=false) for x in c]
    end
    delta(x) = convertvalue(typeof(Δt), x; warn=false)
    v = filter!(r -> r[i] >= t && iszero(delta(r[i] - t) % Δt), df)
    v[1, i] != t && error("incompatible index for initial time = $t\n$v")
    !all(isequal(Δt), delta.(diff(v[!, i]))) && error("incompatible index for time step = $Δt\n$v")
    V = _type
    Provide{V}(v)
end

supportedtags(::Val{:Provide}) = (:index, :init, :step, :autounit, :parameter)
constructortags(::Val{:Provide}) = (:index, :init, :step, :autounit)

updatetags!(d, ::Val{:Provide}; _...) = begin
    !haskey(d, :index) && (d[:index] = QuoteNode(:index))
    !haskey(d, :init) && (d[:init] = :(context.clock.time))
    !haskey(d, :step) && (d[:step] = :(context.clock.step))
    !haskey(d, :autounit) && (d[:autounit] = true)
end

genvartype(v::VarInfo, ::Val{:Provide}; V, _...) = @q Provide{$V}

gendefault(v::VarInfo, ::Val{:Provide}) = istag(v, :parameter) ? genparameter(v) : genbody(v)

genupdate(v::VarInfo, ::Val{:Provide}, ::MainStep; kw...) = nothing
