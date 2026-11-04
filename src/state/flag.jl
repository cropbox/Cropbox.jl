mutable struct Flag{Bool} <: State{Bool}
    value::Bool
end

Flag(; _value, _...) = begin
    Flag{Bool}(_value)
end

supportedtags(::Val{:Flag}) = (:parameter, :override, :extern, :once, :when)
constructortags(::Val{:Flag}) = ()

genvartype(v::VarInfo, ::Val{:Flag}; _...) = @q Flag{Bool}

gendefault(v::VarInfo, ::Val{:Flag}) = istag(v, :parameter) ? genparameter(v) : false

genupdate(v::VarInfo, ::Val{:Flag}, ::MainStep; kw...) = begin
    istag(v, :override, :parameter) && return nothing
    q = genstore(v)
    if istag(v, :once)
        @q if !$C.value($(symstate(v)))
            $q
        end
    else
        q
    end
end
