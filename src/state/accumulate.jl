mutable struct Accumulate{V,T,R} <: State{V}
    value::V
    time::T
    rate::R
    reset::Bool
end

Accumulate(; unit, time, timeunit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    #V = promote_type(V, typeof(v))
    TU = value(timeunit)
    t = unitfy(value(time), TU)
    T = typeof(t)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    Accumulate{V,T,R}(v, t, zero(R), false)
end

constructortags(::Val{:Accumulate}) = (:unit, :init, :time, :timeunit)

@generated rateunit(::Accumulate{V,T,R}) where {V,T,R} = unittype(R)

updatetags!(d, ::Val{:Accumulate}; _...) = begin
    N = d[:_type]
    U = d[:unit]
    !haskey(d, :init) && (d[:init] = @q zero($N))
    !haskey(d, :time) && (d[:time] = :(context.clock.time))
    #TODO: automatic inference without explicit `timeunit` tag
    !haskey(d, :timeunit) && (d[:timeunit] = @q $C.timeunittype($U, $C.timeunit(__Context__)))
    !haskey(d, :reset) && (d[:reset] = false)
end

genvartype(v::VarInfo, ::Val{:Accumulate}; N, U, V, _...) = begin
    TU = gettag(v, :timeunit)
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Accumulate{$V,$T,$R}
end

gendefault(v::VarInfo, ::Val{:Accumulate}) = begin
    i = gettag(v, :init)
    u = gettag(v, :unit)
    @q $C.unitfy($C.value($i), $C.value($u))
end

genupdate(v::VarInfo, ::Val{:Accumulate}, ::MainStep; kw...) = begin
    @gensym s a0 t t0 a
    @q let $s = $(symstate(v)),
           $a0 = $s.reset ? $(gendefault(v)) : $s.value,
           $t = $C.value($(gettag(v, :time))),
           $t0 = $s.time,
           $a = $a0 + $s.rate * ($t - $t0)
        $C.store!($s, $a)
    end
end

genupdate(v::VarInfo, ::Val{:Accumulate}, ::PostStep; kw...) = begin
    w = gettag(v, :when)
    f = isnothing(w) ? genbody(v) : @q $C.value($w) ? $(genbody(v)) : zero($(gettag(v, :_type)))
    @gensym s t r e
    @q let $s = $(symstate(v)),
           $t = $C.value($(gettag(v, :time))),
           $r = $C.unitfy($f, $C.rateunit($s)),
           $e = $C.value($(gettag(v, :reset)))
        $s.time = $t
        $s.rate = $r
        $s.reset = $e
    end
end
