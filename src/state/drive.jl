mutable struct Drive{V} <: State{V}
    value::V
    array::Vector{V}
    tick::Int
end

Drive(; tick, unit, _value, _type, _...) = begin
    t = value(tick)
    U = value(unit)
    V = valuetype(_type, U)
    a = _value
    v = a[1]
    Drive{V}(v, a, t)
end

supportedtags(::Val{:Drive}) = (:tick, :unit, :from, :by, :parameter, :override)
constructortags(::Val{:Drive}) = (:tick, :unit)

updatetags!(d, ::Val{:Drive}; _...) = begin
    !haskey(d, :tick) && (d[:tick] = :(context.clock.tick))
end

genvartype(v::VarInfo, ::Val{:Drive}; V, _...) = @q Drive{$V}

gendefault(v::VarInfo, ::Val{:Drive}) = begin
    s = gettag(v, :from)
    x = if isnothing(s)
        k = gettag(v, :by)
        !isnothing(k) && error("missing `from` provider for `by` = $k")
        istag(v, :parameter) ? genparameter(v) : genbody(v)
    else
        istag(v, :parameter) && error("`parameter` is not allowed with provider: $s")
        !isnothing(v.body) && error("function body is not allowed with provider: $s\n$(v.body)")
        #HACK: needs quot if key is a symbol from VarInfo name
        k = gettag(v, :by, Meta.quot(v.name))
        @q $C.value($s)[!, $k]
    end
    u = gettag(v, :unit)
    @q $C.unitfy($x, $C.value($u))
end

genupdate(v::VarInfo, ::Val{:Drive}, ::MainStep; kw...) = begin
    t = gettag(v, :tick)
    @gensym s t0 t1 i e
    @q let $s = $(symstate(v)),
           $t0 = $s.tick,
           $t1 = $C.value($t),
           $i = $t1 - $t0 + 1,
           $e = $s.array[$i]
        $C.store!($s, $e)
    end
end
