import QuadGK

mutable struct Integrate{V} <: State{V}
    value::V
end

Integrate(; unit, _type, _...) = begin
    V = valuetype(_type, value(unit))
    v = zero(V)
    Integrate{V}(v)
end

constructortags(::Val{:Integrate}) = (:unit,)

updatetags!(d, ::Val{:Integrate}; _...) = begin
    !haskey(d, :from) && (d[:from] = @q zero($(d[:_type])))
    !haskey(d, :to) && (d[:to] = @q zero($(d[:_type])))
end

genvartype(v::VarInfo, ::Val{:Integrate}; V, _...) = @q Integrate{$V}

geninit(v::VarInfo, ::Val{:Integrate}) = nothing

genupdate(v::VarInfo, ::Val{:Integrate}, ::MainStep) = begin
    @gensym s u a b f i
    @q let $s = $(symstate(v)),
           $u = $C.value($(gettag(v, :unit))),
           $a = $C.unitfy($C.value($(gettag(v, :from))), $u),
           $b = $C.unitfy($C.value($(gettag(v, :to))), $u),
           $f = $(genfunc(v))
        $i = $C.QuadGK.quadgk($f, $a, $b) |> first
        $C.store!($s, $i)
    end
end
