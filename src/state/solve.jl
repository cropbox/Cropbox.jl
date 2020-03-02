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
solvepolynomial(p, u=nothing) = begin
    isnothing(u) && (u = u"NoUnits")
    u1 = unit(p[1])
    sp = [deunitfy(q, Unitful.upreferred(u1 / u^(i-1))) for (i, q) in enumerate(p)]
    PolynomialRoots.roots(sp)
end

genrootfunc(v::VarInfo) = begin
    root = gettag(v, :root)
    @capture(root, :(r_))
    #TODO: more general approach (i.e. functional composition)
    if r == :upper
        :maximum
    elseif r == :lower
        :minimum
    else
        error("unrecognized root selection method: $r")
    end
end

updatetags!(d, ::Val{:Solve}; _...) = begin
    !haskey(d, :root) && (d[:root] = :upper)
end

genvartype(v::VarInfo, ::Val{:Solve}; V, _...) = @q Solve{$V}

geninit(v::VarInfo, ::Val{:Solve}) = nothing

genupdate(v::VarInfo, ::Val{:Solve}, ::MainStep) = begin
    U = gettag(v, :unit)
    poly = genpolynomial(v)
    root = genrootfunc(v)
    @gensym r
    body = @q let $r = $C.solvepolynomial([$(esc.(poly)...)], $U)
        filter(isreal, $r) .|> real |> $root
    end
    val = genfunc(v, body)
    genstore(v, val)
end
