mutable struct Remember{V} <: State{V}
    value::V
    done::Bool
end

Remember(; unit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    Remember{V}(v, false)
end

constructortags(::Val{:Remember}) = (:unit,)

genvartype(v::VarInfo, ::Val{:Remember}; V, _...) = @q Remember{$V}

gendefault(v::VarInfo, ::Val{:Remember}) = begin
    N = gettag(v, :_type)
    U = gettag(v, :unit)
    i = gettag(v, :init)
    if isnothing(i)
        @q zero($C.valuetype($N, $U))
    else
        @q $C.unitfy($C.value($i), $C.value($U))
    end
end

genupdate(v::VarInfo, ::Val{:Remember}, ::MainStep; kw...) = begin
    w = gettag(v, :when)
    @gensym s
    @q let $s = $(symstate(v))
        if !($s.done) && $C.value($w)
            $(genstore(v; when=false))
            $s.done = true
        end
    end
end
