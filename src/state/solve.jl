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
    V = extractfuncargkey.(v.args)
    p = eval(@q let $(V...)
        SymPy.@vars $(V...)
        sympy.Poly(begin
            $(v.body)
        end, $x)
    end)
    Q = p.coeffs() |> reverse .|> SymPy.simplify
    Q .|> repr .|> Meta.parse
end

genvartype(v::VarInfo, ::Val{:Solve}; V, _...) = @q Solve{$V}

geninit(v::VarInfo, ::Val{:Solve}) = nothing

genupdate(v::VarInfo, ::Val{:Solve}, ::MainStep) = begin
    poly = genpolynomial(v)
    @gensym r
    body = @q let $r = $C.PolynomialRoots.roots([$(esc.(E)...)])
        $r |> real |> maximum
    end
    val = genfunc(v, body)
    genstore(v, val)
end
