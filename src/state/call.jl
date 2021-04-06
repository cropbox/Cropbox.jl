#TODO: use vendored FunctionWrappers for now: https://github.com/JuliaLang/julia/issues/40187
include("../../lib/FunctionWrappers/FunctionWrappers.jl")
using .FunctionWrappers: FunctionWrapper
struct Call{V,F<:FunctionWrapper} <: State{V}
    value::F
end

Call(; unit, _value, _type, _calltype, _...) = begin
    V = valuetype(_type, value(unit))
    F = _calltype
    Call{V,F}(_value)
end

(c::Call)(a...) = value(c)(a...)

constructortags(::Val{:Call}) = (:unit,)

#HACK: showing s.value could trigger StackOverflowError
Base.show(io::IO, s::Call) = print(io, "<call>")

gencallargtype(t) = isnothing(t) ? :Float64 : esc(t)

updatetags!(d, ::Val{:Call}; kwargs, _...) = begin
    #FIXME: lower duplicate efforts in genvartype()
    N = d[:_type]
    U = d[:unit]
    V = @q $C.valuetype($N, $U)
    extract(a) = let k, t, u
        @capture(a, k_::t_(u_) | k_::t_ | k_(u_) | k_)
        @q $C.valuetype($(gencallargtype(t)), $u)
    end
    F = @q FunctionWrapper{$V, Tuple{$(extract.(kwargs)...)}}
    d[:_calltype] = F
end

genvartype(v::VarInfo, ::Val{:Call}; V, _...) = begin
    extract(a) = let k, t, u
        @capture(a, k_::t_(u_) | k_::t_ | k_(u_) | k_)
        @q $C.valuetype($(gencallargtype(t)), $u)
    end
    F = @q FunctionWrapper{$V, Tuple{$(extract.(v.kwargs)...)}}
    @q Call{$V,$F}
end

geninit(v::VarInfo, ::Val{:Call}) = genfunc(v)

genupdate(v::VarInfo, ::Val{:Call}, ::MainStep; kw...) = genvalue(v)
