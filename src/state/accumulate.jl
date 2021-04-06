mutable struct Accumulate{V,T,R} <: State{V}
    value::V
    time::T
    rate::R
end

Accumulate(; unit, time, timeunit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = isnothing(_value) ? unitfy(zero(_type), U) : _value
    #V = promote_type(V, typeof(v))
    TU = value(timeunit)
    t = unitfy(value(time), TU)
    T = typeof(t)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    Accumulate{V,T,R}(v, t, zero(R))
end

constructortags(::Val{:Accumulate}) = (:unit, :time, :timeunit)

@generated rateunit(::Accumulate{V,T,R}) where {V,T,R} = unittype(R)

updatetags!(d, ::Val{:Accumulate}; _...) = begin
    !haskey(d, :time) && (d[:time] = :(context.clock.time))
    #TODO: automatic inference without explicit `timeunit` tag
    !haskey(d, :timeunit) && (d[:timeunit] = @q $C.timeunittype($(d[:unit]), $C.timeunit(__Context__)))
end

genvartype(v::VarInfo, ::Val{:Accumulate}; N, U, V, _...) = begin
    TU = gettag(v, :timeunit)
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Accumulate{$V,$T,$R}
end

geninit(v::VarInfo, ::Val{:Accumulate}) = begin
    i = gettag(v, :init)
    u = gettag(v, :unit)
    @q $C.unitfy($C.value($i), $C.value($u))
end

genupdate(v::VarInfo, ::Val{:Accumulate}, ::MainStep; kw...) = begin
    @gensym s t t0 a
    @q let $s = $(symstate(v)),
           $t = $C.value($(gettag(v, :time))),
           $t0 = $s.time,
           $a = $s.value + $s.rate * ($t - $t0)
        $C.store!($s, $a)
    end
end

genupdate(v::VarInfo, ::Val{:Accumulate}, ::PostStep; kw...) = begin
    w = gettag(v, :when)
    f = isnothing(w) ? genbody(v) : @q $C.value($w) ? $(genbody(v)) : zero($(gettag(v, :_type)))
    @gensym s t r
    @q let $s = $(symstate(v)),
           $t = $C.value($(gettag(v, :time))),
           $r = $C.unitfy($f, $C.rateunit($s))
        $s.time = $t
        $s.rate = $r
    end
end
