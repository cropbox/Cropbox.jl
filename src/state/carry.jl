mutable struct Carry{V} <: State{V}
    value::Vector{V}
    index::Int
end

Carry(; unit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    Carry{V}(v, 0)
end

constructortags(::Val{:Carry}) = (:from, :by, :unit,)

value(s::Carry) = s.value[s.index]

genvartype(v::VarInfo, ::Val{:Carry}; V, _...) = @q Carry{$V}

geninit(v::VarInfo, ::Val{:Carry}) = begin
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

genupdate(v::VarInfo, ::Val{:Carry}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $s.index += 1
        $C.value($s)
    end
end
