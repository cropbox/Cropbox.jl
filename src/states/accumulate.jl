mutable struct Accumulate{V,T,R} <: State{V}
    value::V
    tick::T
    rate::R
end

Accumulate(; unit, time, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = isnothing(_value) ? unitfy(zero(_type), U) : _value
    V = promote_type(V, typeof(v))
    t = value(time)
    T = typeof(t)
    TU = unittype(T)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    Accumulate{V,T,R}(v, t, zero(R))
end

@generated rateunit(::Accumulate{V,T,R}) where {V,T,R} = unittype(R)

updatetags!(d, ::Val{:Accumulate}; _...) = begin
    !haskey(d, :time) && (d[:time] = :(context.clock.tick))
end

genvartype(v::VarInfo, ::Val{:Accumulate}; N, U, V, _...) = begin
    #TODO: automatic inference without explicit `timeunit` tag
    TU = gettag(v, :timeunit)
    TU = isnothing(TU) ? @q(u"hr") : TU
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Accumulate{$V,$T,$R}
end

geninit(v::VarInfo, ::Val{:Accumulate}) = @q $C.unitfy($C.value($(gettag(v, :init))), $C.value($(v.tags[:unit])))

genupdate(v::VarInfo, ::Val{:Accumulate}, ::MainStep) = begin
    @gensym s t t0 a
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $t0 = $s.tick,
           $a = $s.value + $s.rate * ($t - $t0)
        $C.store!($s, $a)
    end
end

genupdate(v::VarInfo, ::Val{:Accumulate}, ::PostStep) = begin
    @gensym s t f r q
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $f = $(genfunc(v)),
           $r = $C.unitfy($f, $C.rateunit($s)),
           $q = context.queue
        $C.queue!($q, () -> ($s.tick = $t; $s.rate = $r), $C.priority($C.$(v.state)))
    end
end
