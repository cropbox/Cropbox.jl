mutable struct Flag{Bool} <: State{Bool}
    value::Bool
end

Flag(; _value, _...) = begin
    Flag{Bool}(_value)
end

genvartype(v::VarInfo, ::Val{:Flag}; _...) = @q Flag{Bool}

geninit(v::VarInfo, ::Val{:Flag}) = false

genupdate(v::VarInfo, ::Val{:Flag}, ::MainStep) = nothing

genupdate(v::VarInfo, ::Val{:Flag}, ::PostStep) = begin
    @gensym s f q
    if istag(v, :oneway)
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v)),
               $q = context.queue
            if !$C.value($s)
                $C.queue!($q, () -> $C.store!($s, $f), $C.priority($C.$(v.state)))
            end
        end
    else
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v)),
               $q = context.queue
            $C.queue!($q, () -> $C.store!($s, $f), $C.priority($C.$(v.state)))
        end
    end
end
