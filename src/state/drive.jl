mutable struct Drive{V} <: State{V}
    value::V
    array::Vector{V}
    index::Int
end

Drive(; unit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    a = _value
    v = a[1]
    Drive{V}(v, a, 1)
end

constructortags(::Val{:Drive}) = (:from, :by, :unit,)

genvartype(v::VarInfo, ::Val{:Drive}; V, _...) = @q Drive{$V}

geninit(v::VarInfo, ::Val{:Drive}) = begin
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

genupdate(v::VarInfo, ::Val{:Drive}, ::MainStep) = begin
    @gensym s e
    @q let $s = $(symstate(v)),
           $e = $s.array[$s.index]
        $s.index += 1
        $C.store!($s, $e)
    end
end
