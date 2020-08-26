mutable struct Solve{V} <: State{V}
    value::V
end

Solve(; unit, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = zero(V)
    Solve{V}(v)
end

constructortags(::Val{:Solve}) = (:unit,)

#TODO: seems not working inside package?
import Suppressor: @suppress
@suppress import Reduce
#TODO: precompilation error on Julia 1.5+ should be fixed: https://github.com/chakravala/Reduce.jl/issues/32
@suppress Reduce.Preload()
import Printf: @sprintf
gensolution(v::VarInfo) = gensolution(v.body, v.name)
gensolution(body, name) = begin
    extract(ex) = begin
        ex = ex |> MacroTools.rmlines |> MacroTools.unblock
        if MacroTools.isexpr(ex, :block)
            a = ex.args
            (a[1:end-1], a[end])
        else
            #HACK: clean up rhs (i.e. :(2x = 1))
            @capture(ex, f_ = g_) && (ex = @q $f = $(MacroTools.unblock(g)))
            ([], ex)
        end
    end
    subs, eq = extract(body)

    escape(s::Symbol) = map(x -> @sprintf("!#%04x;", x), codepoint.(collect(string(s)))) |> join
    escape(s) = s

    equation(ex) = MacroTools.postwalk(ex) do x
        if @capture(x, f_(a__))
            :($f($(escape.(a)...)))
        elseif @capture(x, f_ = g_)
            :($(escape(f)) = $g)
        else
            x
        end
    end
    stringify(ex) = replace(string(ex), '"' => "")

    rsubs = equation.(subs) .|> stringify
    req = equation(eq) |> stringify

    x = name
    c = "solve(sub({$(join(rsubs, ','))}, $req), $x)"
    r = c |> Reduce.rcall |> Reduce.RExpr |> Reduce.parse

    rval(x) = (@capture(x, f_ = g_); g)
    @q ($(esc.(rval.(r))...),)
end

updatetags!(d, ::Val{:Solve}; _...) = begin
    !haskey(d, :lower) && (d[:lower] = -Inf)
    !haskey(d, :upper) && (d[:upper] = Inf)
    !haskey(d, :pick) && (d[:pick] = QuoteNode(:maximum))
end

genvartype(v::VarInfo, ::Val{:Solve}; V, _...) = @q Solve{$V}

geninit(v::VarInfo, ::Val{:Solve}) = nothing

genupdate(v::VarInfo, ::Val{:Solve}, ::MainStep) = begin
    U = gettag(v, :unit)
    isnothing(U) && (U = @q(u"NoUnits"))
    lower = gettag(v, :lower)
    upper = gettag(v, :upper)
    pick = gettag(v, :pick).value
    solution = gensolution(v)
    @gensym X xl xu l
    body = @q let $X = $C.unitfy($solution, $U),
                  $xl = $C.unitfy($C.value($lower), $U),
                  $xu = $C.unitfy($C.value($upper), $U)
        $l = filter(x -> $xl <= x <= $xu, $X)
        #TODO: better report error instead of silent clamp?
        isempty($l) && ($l = clamp.($X, $xl, $xu))
        $l |> $pick
    end
    val = genfunc(v, body)
    genstore(v, val)
end
