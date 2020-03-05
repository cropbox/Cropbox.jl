mutable struct Bisect{V,E} <: State{V}
    value::V
    step::Symbol
    N::Int
    a::V
    b::V
    c::V
    d::V
    fa::E
    fb::E
    fc::E
end

Bisect(; unit, evalunit, _type, _...) = begin
    V = valuetype(_type, value(unit))
    E = valuetype(_type, value(evalunit))
    v = zero(V)
    e = zero(E)
    Bisect{V,E}(v, :z, 0, v, v, v, v, e, e, e)
end

@generated evalunit(s::Bisect{V,E}) where {V,E} = unittype(E)

updatetags!(d, ::Val{:Bisect}; _...) = begin
    !haskey(d, :evalunit) && (d[:evalunit] = d[:unit])
    !haskey(d, :maxiter) && (d[:maxiter] = 100)
    !haskey(d, :tol) && (d[:tol] = 0.001)
end

genvartype(v::VarInfo, ::Val{:Bisect}; N, V, _...) = begin
    EU = gettag(v, :evalunit)
    E = @q $C.valuetype($N, $EU)
    @q Bisect{$V,$E}
end

geninit(v::VarInfo, ::Val{:Bisect}) = nothing

genupdate(v::VarInfo, ::Val{:Bisect}, ::MainStep) = begin
    maxiter = gettag(v, :maxiter)
    tol = gettag(v, :tol)
    lstart = symlabel(v, PreStep())
    lexit = symlabel(v, MainStep(), :__exit)
    @gensym s u Δ
    @q let $s = $(symstate(v))
        if $s.step == :z
            $s.N = 1
            $u = $C.value($(gettag(v, :unit)))
            $s.a = $C.unitfy($C.value($(v.tags[:lower])), $u)
            $s.b = $C.unitfy($C.value($(v.tags[:upper])), $u)
            $s.d = $s.b - $s.a
            $s.step = :a
            $C.store!($s, $s.a)
            @goto $lstart
        else
            $s.N += 1
            if $s.N > $maxiter
                @show #= @error =# "bisect: convergence failed!"
                $s.step = :z
                @goto $lexit
            end
        end
        if $s.step == :a
            $s.fa = $(genfunc(v))
            #@show "bisect: $($s.a) => $($s.fa)"
            $s.step = :b
            $C.store!($s, $s.b)
            @goto $lstart
        elseif $s.step == :b
            $s.fb = $(genfunc(v))
            #@show "bisect: $($s.b) => $($s.fb)"
            if sign($s.fa) == sign($s.fb)
                #HACK: try expanding bracket
                #$s.N += round(Int, 0.1*$maxiter)
                $Δ = ($s.b - $s.a) / 2
                $s.a -= $Δ
                $s.b += $Δ
                #@show "bisect: $($s.a) <- a, b -> $($s.b) "
                $s.step = :a
                $C.store!($s, $s.a)
                @goto $lstart
            end
            $s.c = ($s.a + $s.b) / 2
            $C.store!($s, $s.c)
            $s.step = :c
            @goto $lstart
        elseif $s.step == :c
            $s.fc = $(genfunc(v))
            #@show "bisect: $($s.c) => $($s.fc)"
            if $s.fc ≈ zero($s.fc) || ($s.b - $s.a) / $s.d < $tol
                $s.step = :z
                #@show "bisect: finished! $($C.value($s))"
                @goto $lexit
            end
            if sign($s.fc) == sign($s.fa)
                $s.a = $s.c
                $s.fa = $s.fc
                #@show "bisect: a <- $($s.c)"
            else
                $s.b = $s.c
                $s.fb = $s.fc
                #@show "bisect: b <- $($s.c)"
            end
            $s.c = ($s.a + $s.b) / 2
            $C.store!($s, $s.c)
            @goto $lstart
        end
        @label $lexit
        $C.value($s)
    end
end
