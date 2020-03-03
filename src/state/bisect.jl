mutable struct Bisect{V} <: State{V}
    value::V
    step::Symbol
    N::Int
    a::V
    b::V
    c::V
    fa::V
    fb::V
    fc::V
end

Bisect(; unit, _type, _...) = begin
    V = valuetype(_type, value(unit))
    v = zero(V)
    Bisect{V}(v, :z, 0, v, v, v, v, v, v)
end

genvartype(v::VarInfo, ::Val{:Bisect}; V, _...) = @q Bisect{$V}

geninit(v::VarInfo, ::Val{:Bisect}) = nothing

genupdate(v::VarInfo, ::Val{:Bisect}, ::MainStep) = begin
    N_MAX = 100
    TOL = 0.01
    lstart = symlabel(v, PreStep())
    lexit = symlabel(v, MainStep(), :__exit)
    @gensym s u
    @q let $s = $(symstate(v))
        if $s.step == :z
            $s.N = 0
            $u = $C.value($(gettag(v, :unit)))
            $s.a = $C.unitfy($C.value($(v.tags[:lower])), $u)
            $s.b = $C.unitfy($C.value($(v.tags[:upper])), $u)
            $s.step = :a
            $C.store!($s, $s.a)
            @goto $lstart
        elseif $s.step == :a
            $s.fa = $C.value($s) - $(genfunc(v))
            #@show "bisect: $($s.a) => $($s.fa)"
            $s.step = :b
            $C.store!($s, $s.b)
            @goto $lstart
        elseif $s.step == :b
            $s.fb = $C.value($s) - $(genfunc(v))
            #@show "bisect: $($s.b) => $($s.fb)"
            @assert sign($s.fa) != sign($s.fb)
            $s.N = 1
            $s.c = ($s.a + $s.b) / 2
            $C.store!($s, $s.c)
            $s.step = :c
            @goto $lstart
        elseif $s.step == :c
            $s.fc = $C.value($s) - $(genfunc(v))
            #@show "bisect: $($s.c) => $($s.fc)"
            if $s.fc ≈ zero($s.fc) || ($s.b - $s.a) / ($s.b) < $TOL
                $s.step = :z
                #@show "bisect: finished! $($C.value($s))"
                @goto $lexit
            else
                $s.N += 1
                if $s.N > $N_MAX
                    @show #= @error =# "bisect: convergence failed!"
                    $s.step = :z
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
        end
        @label $lexit
        $C.value($s)
    end
end
