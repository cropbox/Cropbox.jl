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
    Q = p.coeffs()
    #HACK: normalize coefficient to avoid runtime unit generation
    Q = Q / Q[1] |> reverse .|> SymPy.simplify
    Q .|> repr .|> Meta.parse
end
genpolynomialunits(U, n) = [@q($U^$(i-1)) for i in n:-1:1]

import PolynomialRoots
solvepolynomial(p, pu, u) = begin
    sp = [deunitfy(q, qu) for (q, qu) in zip(p, pu)]
    r = PolynomialRoots.roots(sp)
    unitfy(real.(filter(isreal, r)), u)
end

updatetags!(d, ::Val{:Solve}; _...) = begin
    #HACK: `end` causes missing variable dependency
    #!haskey(d, :order) && (d[:order] = :(:end))
    !haskey(d, :lower) && (d[:lower] = -Inf)
    !haskey(d, :upper) && (d[:upper] = Inf)
end

genvartype(v::VarInfo, ::Val{:Solve}; V, _...) = @q Solve{$V}

geninit(v::VarInfo, ::Val{:Solve}) = nothing

genupdate(v::VarInfo, ::Val{:Solve}, ::MainStep) = begin
    U = gettag(v, :unit)
    isnothing(U) && (U = @q(u"NoUnits"))
    P = genpolynomial(v)
    PU = genpolynomialunits(U, length(P))
    #HACK: pick last one as it seems align with our use (i.e. upper for hs, lower for J)
    order = gettag(v, :order, :end)
    lower = gettag(v, :lower)
    upper = gettag(v, :upper)
    @gensym r a b l
    body = @q let $r = $C.solvepolynomial([$(esc.(P)...)], [$(PU...)], $U),
                  $a = $C.unitfy($C.value($lower), $U),
                  $b = $C.unitfy($C.value($upper), $U)
        # $l = filter(x -> $a <= x <= $b, $r)
        # isempty($l) && ($l = clamp.($r, $a, $b))
        $l = $r
        $l[$order]
    end
    val = genfunc(v, body)
    genstore(v, val)
end
