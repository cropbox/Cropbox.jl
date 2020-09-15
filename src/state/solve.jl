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

# \Equal opeartor for both solve/bisect
⩵(x, y) = x - y
export ⩵

using SymPy: SymPy, sympy
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
solvepolynomial(p, pu) = begin
    sp = [deunitfy(q, qu) for (q, qu) in zip(p, pu)]
    r = PolynomialRoots.roots(sp)
    real.(filter(isreal, r))
end
solvequadratic(a, b, c) = begin
    (a == 0) && return (-c/b,)
    Δ = b^2 - 4a*c
    if Δ > 0
        s = √Δ
        ((-b - s) / 2a, (-b + s) / 2a)
    elseif Δ == 0
        (-b/2a,)
    else
        #HACK: make up a non-complex solution
        x = -b/2a
        @warn "ignore complex roots for quadratic equation: $a*x^2 + $b*x + $c = 0" x
        (x,)
    end
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
    P = genpolynomial(v)
    n = length(P)
    PU = genpolynomialunits(U, n)
    lower = gettag(v, :lower)
    upper = gettag(v, :upper)
    pick = gettag(v, :pick).value
    body = if n == 2 # linear
        @gensym a b xl xu
        @q let $a = $(esc(P[2])),
               $b = $(esc(P[1])),
               $xl = $C.unitfy($C.value($lower), $U),
               $xu = $C.unitfy($C.value($upper), $U)
            clamp(-$b / $a, $xl, $xu)
        end
    elseif n == 3 # quadratic
        @gensym a b c X xl xu l
        @q let $a = $C.deunitfy($(esc(P[3])), $(PU[3])),
               $b = $C.deunitfy($(esc(P[2])), $(PU[2])),
               $c = $C.deunitfy($(esc(P[1])), $(PU[1])),
               $X = $C.unitfy($C.solvequadratic($a, $b, $c), $U),
               $xl = $C.unitfy($C.value($lower), $U),
               $xu = $C.unitfy($C.value($upper), $U)
            #TODO: remove duplication
            $l = filter(x -> $xl <= x <= $xu, collect($X))
            isempty($l) && ($l = clamp.($X, $xl, $xu))
            $l |> $pick
        end
    else # generic polynomials (slow!)
        @gensym X xl xu l
        @q let $X = $C.unitfy($C.solvepolynomial([$(esc.(P)...)], [$(PU...)]), $U),
               $xl = $C.unitfy($C.value($lower), $U),
               $xu = $C.unitfy($C.value($upper), $U)
            $l = filter(x -> $xl <= x <= $xu, $X)
            #TODO: better report error instead of silent clamp?
            isempty($l) && ($l = clamp.($X, $xl, $xu))
            $l |> $pick
        end
    end
    val = genbody(v, body)
    genstore(v, val)
end
