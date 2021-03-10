mutable struct Flag{Bool} <: State{Bool}
    value::Bool
end

Flag(; _value, _...) = begin
    Flag{Bool}(_value)
end

constructortags(::Val{:Flag}) = ()

genvartype(v::VarInfo, ::Val{:Flag}; _...) = @q Flag{Bool}

geninit(v::VarInfo, ::Val{:Flag}) = false

genupdate(v::VarInfo, ::Val{:Flag}, ::MainStep) = istag(v, :lazy) ? nothing : genflag(v)

genupdate(v::VarInfo, ::Val{:Flag}, ::PostStage) = istag(v, :lazy) ? genflag(v) : nothing

genflag(v::VarInfo) = begin
    @gensym s f q
    if istag(v, :oneway)
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
