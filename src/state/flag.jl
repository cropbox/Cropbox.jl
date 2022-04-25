mutable struct Flag{Bool} <: State{Bool}
    value::Bool
end

Flag(; _value, _...) = begin
    Flag{Bool}(_value)
end

constructortags(::Val{:Flag}) = ()

genvartype(v::VarInfo, ::Val{:Flag}; _...) = @q Flag{Bool}

gendefault(v::VarInfo, ::Val{:Flag}) = istag(v, :parameter) ? genparameter(v) : false

genupdate(v::VarInfo, ::Val{:Flag}, ::MainStep; kw...) = begin
    @gensym s f q
    if istag(v, :override, :parameter)
        nothing
    elseif istag(v, :once)
        @q let $s = $(symstate(v))
            if !$C.value($s)
                let $f = $(genbody(v))
                    $C.store!($s, $f)
                end
            end
        end
    else
        @q let $s = $(symstate(v)),
               $f = $(genbody(v))
            $C.store!($s, $f)
        end
    end
end
