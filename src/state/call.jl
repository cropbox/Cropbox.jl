import FunctionWrappers: FunctionWrapper
struct Call{V,F<:FunctionWrapper} <: State{V}
    value::F
end

Call(; unit, _value, _type, _calltype, _...) = begin
    V = valuetype(_type, value(unit))
    F = _calltype
    Call{V,F}(_value)
end

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

geninit(v::VarInfo, ::Val{:Call}) = begin
    emiti(a) = (p = extractfuncargpair(a); @q $(esc(p[1])) = $C.value($(p[2])))
    innerargs = @q begin $(emiti.(v.args)...) end

    innercall = MacroTools.flatten(@q let $innerargs; $(esc(v.body)) end)
    innerbody = @q $C.unitfy($innercall, $C.value($(v.tags[:unit])))

    emito(a) = (p = extractfuncargpair(a); @q $(esc(p[1])) = $(p[2]))
    outerargs = @q begin $(emito.(v.args)...) end

    extract(a) = let k, t, u; @capture(a, k_::t_(u_) | k_::t_ | k_(u_)) ? k : a end
    emitc(a) = @q $(esc(extract(a)))
    callargs = emitc.(v.kwargs)

    @q function $(symcall(v))($(callargs...))
        $innerbody
    end
    # outerbody = MacroTools.flatten(@q let $outerargs
    #     function $(symcall(v))($(callargs...))
    #         $innerbody
    #     end
    # end)
    #
    # key(a) = let k, v; @capture(a, k_=v_) ? k : a end
    # emitf(a) = @q $(esc(key(a)))
    # fillargs = emitf.(v.args)
    #
    # @q function $(symcall(v))($(fillargs...); $(callargs...)) $outerbody end
end

genupdate(v::VarInfo, ::Val{:Call}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $C.value($s)
    end
end
