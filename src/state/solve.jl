mutable struct Solve{V} <: State{V}
    value::V
end

Solve(; unit, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = zero(V)
    Solve{V}(v)
end

supportedtags(::Val{:Solve}) = (:unit, :lower, :upper, :pick)
constructortags(::Val{:Solve}) = (:unit,)

# \Equal opeartor for both solve/bisect
⩵(x, y) = x - y
export ⩵

import Symbolics
genpolynomial(v::VarInfo; scope) = begin
    x = v.name
    V = extractfuncargpair.(v.args) .|> first
    push!(V, x)
    #HACK: use scope of caller, avoiding eval into precompiled Cropbox module
    scope.eval(@q let $(V...)
        Cropbox.Symbolics.@variables $(V...)
        Cropbox.polynomialcoefficients(begin
            $(v.body)
        end, $x)
    end)
end
polynomialcoefficients(p, x) = begin
    terms, residual = Symbolics.semipolynomial_form(p, [x], Inf)
    iszero(Symbolics.Num(Symbolics.simplify(residual))) ||
        throw(ArgumentError("solve requires a polynomial in $x; residual: $residual"))
    n = maximum((Int(Symbolics.degree(m, x)) for m in keys(terms)); init=0)
    Q = fill(Symbolics.Num(0), n+1)
    for (m, c) in terms
        Q[Int(Symbolics.degree(m, x))+1] = c
    end
    Q
end
genpolynomialexpr(p) = begin
    ex = Symbolics.simplify(p) |> Symbolics.toexpr
    # Preserve numeric division without overflowing intermediate Rational values.
    MacroTools.postwalk(x -> x isa Rational ? float(x) : x, ex)
end
genpolynomialunits(U, n) = [@q($U^$(i-1)) for i in n:-1:1]

import PolynomialRoots
solvepolynomial(p, pu) = begin
    sp = [deunitfy(q, qu) for (q, qu) in zip(p, pu)]
    r = PolynomialRoots.roots(sp)
    real.(filter!(x -> isreal(x) || abs(imag(x)) <= eps(real(x)), r))
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

gendefault(v::VarInfo, ::Val{:Solve}) = nothing

genupdate(v::VarInfo, ::Val{:Solve}, ::MainStep; scope, kw...) = begin
    U = gettag(v, :unit)
    isnothing(U) && (U = @q(u"NoUnits"))
    lower = gettag(v, :lower)
    upper = gettag(v, :upper)
    pick = gettag(v, :pick).value
    body = genpolynomialbody(genpolynomial(v; scope); U, lower, upper, pick)
    val = genbody(v, body)
    genstore(v, val)
end

genpolynomialbody(Q; U, lower, upper, pick) = begin
    n = length(Q)
    n < 2 && return @q throw(ArgumentError("solve requires a nonzero nonconstant coefficient"))
    leading = genpolynomialexpr(Q[end])
    fallback() = genpolynomialbody(Q[1:end-1]; U, lower, upper, pick)
    leading isa Number && iszero(leading) && return fallback()
    # Normalize each degree separately to avoid runtime unit generation.
    P = genpolynomialexpr.(Q ./ Q[end])
    PU = genpolynomialunits(U, n)
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
            $l = filter(x -> $xl <= x <= $xu, $X)
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
    leading isa Number && return body
    @q if iszero($(esc(leading)))
        $(fallback())
    else
        $body
    end
end
