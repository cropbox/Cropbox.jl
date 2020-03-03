mutable struct Solve{V} <: State{V}
    value::V
end

Solve(; unit, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = zero(V)
    Solve{V}(v)
end

import SymPy: SymPy, sympy, ⩵
export ⩵
genpolynomial(v::VarInfo) = begin
    x = v.name
    V = extractfuncargpair.(v.args) .|> first
    push!(V, x)
    p = eval(@q let $(V...)
        SymPy.@vars $(V...)
        sympy.Poly(begin
            $(v.body)
        end, $x)
    end)
    Q = p.coeffs() |> reverse .|> SymPy.simplify
    Q .|> repr .|> Meta.parse
end

import PolynomialRoots
import Unitful: upreferred
solvepolynomial(p, u=nothing) = begin
    isnothing(u) && (u = u"NoUnits")
    u = u |> upreferred
    u1 = unit(p[1]) |> upreferred
    sp = [deunitfy(q, u1 / u^(i-1)) for (i, q) in enumerate(p)]
    r = PolynomialRoots.roots(sp)
    real.(filter(isreal, r)) * u
end

updatetags!(d, ::Val{:Solve}; _...) = begin
    !haskey(d, :order) && (d[:order] = 1)
    !haskey(d, :lower) && (d[:lower] = -Inf)
    !haskey(d, :upper) && (d[:upper] = Inf)
end

genvartype(v::VarInfo, ::Val{:Solve}; V, _...) = @q Solve{$V}

geninit(v::VarInfo, ::Val{:Solve}) = nothing

genupdate(v::VarInfo, ::Val{:Solve}, ::MainStep) = begin
    U = gettag(v, :unit)
    poly = genpolynomial(v)
    order = gettag(v, :order)
    lower = gettag(v, :lower)
    upper = gettag(v, :upper)
    @gensym r a b l
    body = @q let $r = $C.solvepolynomial([$(esc.(poly)...)], $U)#,
                  #$a = $C.unitfy($C.value($lower), $U),
                  #$b = $C.unitfy($C.value($upper), $U)
        # @show $r
        # @show $a
        # @show $b
        #filter(isreal, $r) .|> real |> $root
        #$rr = real.(filter(isreal, $r))
        # @show $rr
        # $l = filter(x -> $a <= x <= $b, $r)
        # # @show $l
        # isempty($l) && ($l = clamp.($r, $a, $b))
        $l = $r
        $l[$order]
    end
    val = genfunc(v, body)
    genstore(v, val)
end
