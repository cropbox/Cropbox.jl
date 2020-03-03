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
# solvepolynomial(p, pu, u) = begin
#     sp = [deunitfy(q, qu) for (q, qu) in zip(p, pu)]
#     r = PolynomialRoots.roots(sp)
#     #unitfy(real.(filter(isreal, r)), u)
#     real.(filter(isreal, r))
# end
# solvepolynomial(p, pu, u) = begin
#     sp = [deunitfy(q, qu) for (q, qu) in zip(p, pu)]
#     r = quadratic_solve(sp...)
#     #unitfy(r, u)
#     r
# end
solvepolynomial(p, pu, u, o) = begin
    sp = [deunitfy(q, qu) for (q, qu) in zip(p, pu)]
    r = if o == 1
        quadratic_solve_upper(sp...)
    elseif o == 2
        quadratic_solve_lower(sp...)
    end
    #unitfy(r, u)
    r
end

quadratic_solve(c, b, a) = begin
    (a == 0) && return [0.]
    v = b^2 - 4a*c
    if v < 0
        [-b/a]
    else
        sv = sqrt(v)
        [(-b - sv) / 2a, (-b + sv) / 2a]
    end
end
quadratic_solve2(c, b, a) = begin
    (a == 0) && return (0.,)
    v = b^2 - 4a*c
    if v < 0
        (-b/a,)
    else
        sv = sqrt(v)
        ((-b - sv) / 2a, (-b + sv) / 2a)
    end
end
quadratic_solve_upper(c, b, a) = begin
    (a == 0) && return 0.
    v = b^2 - 4a*c
    v < 0 ? -b/a : (-b + sqrt(v)) / 2a
end
quadratic_solve_lower(c, b, a) = begin
    (a == 0) && return 0.
    v = b^2 - 4a*c
    v < 0 ? -b/a : (-b - sqrt(v)) / 2a
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
    # body = @q let $r = $C.solvepolynomial([$(esc.(P)...)], [$(PU...)], $U, $order)#,
    #               # $a = $C.unitfy($C.value($lower), $U),
    #               # $b = $C.unitfy($C.value($upper), $U)
    #     # $l = filter(x -> $a <= x <= $b, $r)
    #     # isempty($l) && ($l = clamp.($r, $a, $b))
    #     # #$l = $r
    #     # $l[$order]
    #     $r
    # end
    @gensym p pu sp
    # body = @q let $p = [$(esc.(P)...)],
    #               $pu = [$(PU...)]
    #     $sp = [deunitfy(q, qu) for (q, qu) in zip($p, $pu)]
    #     $r = if $order == 1
    #         quadratic_solve_upper($sp...)
    #     elseif $order == 2
    #         quadratic_solve_lower($sp...)
    #     end
    #     $r
    # end
    @gensym a b c
    # body = @q let $p = [$(esc.(P)...)],
    #               $pu = [$(PU...)],
    #               $c = deunitfy($p[1], $pu[1]),
    #               $b = deunitfy($p[2], $pu[2]),
    #               $a = deunitfy($p[3], $pu[3])
    #     #$sp = [deunitfy(q, qu) for (q, qu) in zip($p, $pu)]
    #     #$sp = [deunitfy($p[i], $pu[i]) for i in 1:$(length(P))]
    #     $r = if $order == 1
    #         #quadratic_solve_upper($sp...)
    #         quadratic_solve_upper($c, $b, $a)
    #     elseif $order == 2
    #         #quadratic_solve_lower($sp...)
    #         quadratic_solve_lower($c, $b, $a)
    #     end
    #     $r
    # end
    # body = @q let $c = deunitfy($(esc(P[1])), $(PU[1])),
    #               $b = deunitfy($(esc(P[2])), $(PU[2])),
    #               $a = deunitfy($(esc(P[3])), $(PU[3]))
    #     $r = if $order == 1
    #         #quadratic_solve_upper($sp...)
    #         quadratic_solve_upper($c, $b, $a)
    #     elseif $order == 2
    #         #quadratic_solve_lower($sp...)
    #         quadratic_solve_lower($c, $b, $a)
    #     end
    #     $r
    # end
    # body = @q let $c = deunitfy($(esc(P[1])), $(PU[1])),
    #               $b = deunitfy($(esc(P[2])), $(PU[2])),
    #               $a = deunitfy($(esc(P[3])), $(PU[3]))
    #     $r = $C.PolynomialRoots.roots([$c, $b, $a])
    #     $l = real.(filter(isreal, $r))
    #     $l[end]
    # end
    # @gensym xl xu a b c r l
    # body = @q let $c = deunitfy($(esc(P[1])), $(PU[1])),
    #               $b = deunitfy($(esc(P[2])), $(PU[2])),
    #               $a = deunitfy($(esc(P[3])), $(PU[3])),
    #               $xl = $C.unitfy($C.value($lower), $U),
    #               $xu = $C.unitfy($C.value($upper), $U)
    #   $r = $C.unitfy(quadratic_solve($c, $b, $a), $U)
    #   $l = filter(x -> $xl <= x <= $xu, $r)
    #   isempty($l) && ($l = clamp.($r, $xl, $xu))
    #   $l[1]
    # end
    @gensym xl xu a b c r l x
    body = @q let $c = deunitfy($(esc(P[1])), $(PU[1])),
                  $b = deunitfy($(esc(P[2])), $(PU[2])),
                  $a = deunitfy($(esc(P[3])), $(PU[3])),
                  $xl = $C.unitfy($C.value($lower), $U),
                  $xu = $C.unitfy($C.value($upper), $U)
      $l = $C.unitfy(quadratic_solve2($c, $b, $a), $U)
      $r = nothing
      for $x in $l
          if $xl <= $x <= $xu
              $r = $x
              break
          end
      end
      isnothing($r) && ($r = clamp($l[1], $xl, $xu))
      $r
    end
    val = genfunc(v, body)
    genstore(v, val)
end
