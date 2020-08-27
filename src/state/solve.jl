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

#HACK: based on a modified version of Reduce.jl: https://github.com/chakravala/Reduce.jl/pull/43
import Reduce
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

    gather(ex) = begin
        l = []
        add(x::Symbol) = push!(l, x)
        add(x) = nothing
        MacroTools.postwalk(ex) do x
           if @capture(x, f_(a__))
               add.(a)
           elseif @capture(x, f_ = g_)
               add(f)
               add(g)
           end
           x
        end
        Set(l)
    end

    F = Dict()
    B = Dict()
    for (i, s) in enumerate(union(gather.([subs..., eq])...))
        v = Symbol("v$i")
        F[s] = v
        B[v] = s
    end
    escape(s::Symbol) = F[s]
    escape(s) = s
    unescape(s::Symbol) = B[s]
    unescape(s) = s

    equation(ex, tr) = MacroTools.prewalk(ex) do x
        if @capture(x, f_(a__))
            :($f($(tr.(a)...)))
        elseif @capture(x, f_ = g_)
            :($(tr(f)) = $(tr(g)))
        else
            x
        end
    end
    stringify(ex) = replace(string(ex), '"' => "")

    rsubs = equation.(subs, escape) .|> stringify
    req = equation(eq, escape) |> stringify

    x = escape(name)
    #HACK: can't use Reduce.Algebra.Sub due to incompatibility with assignment expression
    c = "solve(sub({$(join(rsubs, ','))}, $req), $x)"
    #HACK: restart REDUCE stack
    Reduce.Reset()
    r = c |> Reduce.rcall |> Reduce.RExpr |> Reduce.parse

    solution(ex) = (@capture(ex, f_ = g_) && @assert(f == x); equation(g, unescape))
    @q ($(esc.(solution.(r))...),)
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
