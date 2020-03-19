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

#HACK: needs update in case min/max variables changed during bisection loop
#TODO: other variables wanting to use min/max would require similar work
genupdate(v::VarInfo, ::Val{:Bisect}, ::PreStep) = begin
    @gensym s d
    @q let $s = $(symstate(v)),
           $d = $(genminmax(v, @q $C.value($s)))
        $C.store!($s, $d)
    end
end
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
            $s.a = $(genminmax(v, @q $C.unitfy($C.value($(v.tags[:lower])), $u)))
            $s.b = $(genminmax(v, @q $C.unitfy($C.value($(v.tags[:upper])), $u)))
            $s.d = $s.b - $s.a
            $s.step = :a
            $C.store!($s, $s.a)
            @goto $lstart
        else
            $s.N += 1
            if $s.N > $maxiter
                @warn "bisect[$($s.N)]: convergence failed!" c=$s.c fc=$s.fc d=$s.d $(v.name)=$C.value($s)
                $s.step = :z
                @goto $lexit
            end
        end
        if $s.step == :a
            $s.fa = $(genfunc(v))
            if isnan($s.fa)
                @warn "bisect[$($s.N)]: $($s.a) => $($s.fa)"
            else
                @debug "bisect[$($s.N)]: $($s.a) => $($s.fa)"
            end
            $s.step = :b
            $C.store!($s, $s.b)
            @goto $lstart
        elseif $s.step == :b
            $s.fb = $(genfunc(v))
            if isnan($s.fb)
                @warn "bisect[$($s.N)]: $($s.b) => $($s.fb)"
            else
                @debug "bisect[$($s.N)]: $($s.b) => $($s.fb)"
            end
            if sign($s.fa) == sign($s.fb)
                #HACK: try expanding bracket
                #$s.N += round(Int, 0.1*$maxiter)
                $Δ = ($s.b - $s.a) / 2
                if iszero($Δ)
                    @warn "bisect[$($s.N)]: expansion failed!" $(v.name)=$C.value($s)
                    $s.step = :z
                    @goto $lexit
                end
                #HACK: reduce redundant unitfy when generating min/max clipping
                #TODO: check no expansion case where Δ gets clipped by min/max
                $s.a = $(genminmax(v, @q $s.a - $Δ))
                $s.b = $(genminmax(v, @q $s.b + $Δ))
                @debug "bisect[$($s.N)]: $($s.a) <- a, b -> $($s.b) "
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
            if isnan($s.fc)
                @warn "bisect[$($s.N)]: $($s.c) => $($s.fc)"
            else
                @debug "bisect[$($s.N)]: $($s.c) => $($s.fc)"
            end
            if $s.fc ≈ zero($s.fc) || ($s.b - $s.a) / $s.d < $tol
                @debug "bisect[$($s.N)]: finished! $($C.value($s))"
                $s.step = :z
                @goto $lexit
            end
            if sign($s.fc) == sign($s.fa)
                $s.a = $s.c
                $s.fa = $s.fc
                @debug "bisect[$($s.N)]: a <- $($s.c)"
            else
                $s.b = $s.c
                $s.fb = $s.fc
                @debug "bisect[$($s.N)]: b <- $($s.c)"
            end
            $s.c = ($s.a + $s.b) / 2
            $C.store!($s, $s.c)
            @goto $lstart
        end
        @label $lexit
        $C.value($s)
    end
end
