struct Bring{V} <: State{V}
    value::V
end

Bring(; _value, kw...) = begin
    v = _value
    V = typeof(v)
    V(; kw...)
end

supportedtags(::Val{:Bring}) = (:parameters, :override)
constructortags(::Val{:Bring}) = ()

genvartype(v::VarInfo, ::Val{:Bring}; V, _...) = V

genupdate(v::VarInfo, ::Val{:Bring}, t::PreStep; kw...) = genupdate(v, Val(nothing), t; kw...)
genupdate(v::VarInfo, ::Val{:Bring}, t::MainStep; kw...) = genupdate(v, Val(nothing), t; kw...)
genupdate(v::VarInfo, ::Val{:Bring}, t::PostStep; kw...) = genupdate(v, Val(nothing), t; kw...)

genupdate(v::VarInfo, ::Val{:Bring}, t::PreStage; kw...) = genupdate(v, Val(nothing), t; kw...)
genupdate(v::VarInfo, ::Val{:Bring}, t::PostStage; kw...) = genupdate(v, Val(nothing), t; kw...)
