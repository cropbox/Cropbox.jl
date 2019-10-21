mutable struct Drive{V} <: State{V}
    value::V
end

Drive(; unit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    V = promote_type(V, typeof(v))
    Drive{V}(v)
end

genvartype(v::VarInfo, ::Val{:Drive}; V, _...) = @q Drive{$V}

geninit(v::VarInfo, ::Val{:Drive}) = begin
    k = gettag(v, :key, v.name)
    #HACK: needs quot if key is a symbol from VarInfo name
    k = isa(k, QuoteNode) ? k : Meta.quot(k)
    @q $C.unitfy($C.value($(genfunc(v))[$k]), $C.value($(v.tags[:unit])))
end

genupdate(v::VarInfo, ::Val{:Drive}, ::MainStep) = begin
    k = gettag(v, :key, v.name)
    #HACK: needs quot if key is a symbol from VarInfo name
    k = isa(k, QuoteNode) ? k : Meta.quot(k)
    @gensym s f d
    @q let $s = $(symstate(v)),
           $f = $(genfunc(v)),
           $d = $C.value($f[$k])
        $C.store!($s, $d)
    end # value() for Var
end
