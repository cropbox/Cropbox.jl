mutable struct Capture{V,T,R} <: State{V}
    value::V
    time::T
    rate::R
end

Capture(; unit, time, timeunit, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = unitfy(zero(_type), U)
    #V = promote_type(V, typeof(v))
    TU = value(timeunit)
    t = unitfy(value(time), TU)
    T = typeof(t)
    RU = rateunittype(U, TU)
    R = valuetype(_type, RU)
    Capture{V,T,R}(v, t, zero(R))
end

supportedtags(::Val{:Capture}) = (:unit, :time, :timeunit, :when)
constructortags(::Val{:Capture}) = (:unit, :time, :timeunit)

@generated rateunit(s::Capture{V,T,R}) where {V,T,R} = unittype(R)

updatetags!(d, ::Val{:Capture}; _...) = begin
    !haskey(d, :time) && (d[:time] = :(context.clock.time))
    #TODO: automatic inference without explicit `timeunit` tag
    !haskey(d, :timeunit) && (d[:timeunit] = @q $C.timeunittype($(d[:unit]), $C.timeunit(__Context__)))
end

genvartype(v::VarInfo, ::Val{:Capture}; N, U, V, _...) = begin
    TU = gettag(v, :timeunit)
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Capture{$V,$T,$R}
end

gendefault(v::VarInfo, ::Val{:Capture}) = nothing

genupdate(v::VarInfo, ::Val{:Capture}, ::MainStep; kw...) = begin
    @gensym s t t0 d
    @q let $s = $(symstate(v)),
           $t = $C.value($(gettag(v, :time))),
           $t0 = $s.time,
           $d = $s.rate * ($t - $t0)
        $C.store!($s, $d)
    end
end

genupdate(v::VarInfo, ::Val{:Capture}, ::PostStep; kw...) = begin
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
