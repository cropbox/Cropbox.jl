mutable struct Flag{Bool} <: State{Bool}
    value::Bool
end

Flag(; _value, _...) = begin
    Flag{Bool}(_value)
end

constructortags(::Val{:Flag}) = ()

genvartype(v::VarInfo, ::Val{:Flag}; _...) = @q Flag{Bool}

geninit(v::VarInfo, ::Val{:Flag}) = false

genupdate(v::VarInfo, ::Val{:Flag}, ::MainStep) = nothing

genupdate(v::VarInfo, ::Val{:Flag}, ::PostStage) = begin
    @gensym s f q
    if istag(v, :oneway)
        @q let $s = $(symstate(v))
            if !$C.value($s)
                let $f = $(genfunc(v))
                    $C.store!($s, $f)
                end
            end
        end
    else
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v))
            $C.store!($s, $f)
        end
    end
end
