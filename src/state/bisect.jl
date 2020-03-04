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
end

genvartype(v::VarInfo, ::Val{:Bisect}; N, V, _...) = begin
    EU = gettag(v, :evalunit)
    E = @q $C.valuetype($N, $EU)
    @q Bisect{$V,$E}
end

geninit(v::VarInfo, ::Val{:Bisect}) = nothing

genupdate(v::VarInfo, ::Val{:Bisect}, ::MainStep) = begin
    N_MAX = 100
    TOL = 0.001
    lstart = symlabel(v, PreStep())
    lexit = symlabel(v, MainStep(), :__exit)
    @gensym s u
    @q let $s = $(symstate(v))
        if $s.step == :z
            $s.N = 0
            $u = $C.value($(gettag(v, :unit)))
            $s.a = $C.unitfy($C.value($(v.tags[:lower])), $u)
            $s.b = $C.unitfy($C.value($(v.tags[:upper])), $u)
            $s.d = $s.b - $s.a
            $s.step = :a
            $C.store!($s, $s.a)
            @goto $lstart
        elseif $s.step == :a
            $s.fa = $(genfunc(v))
            #@show "bisect: $($s.a) => $($s.fa)"
            $s.step = :b
            $C.store!($s, $s.b)
            @goto $lstart
        elseif $s.step == :b
            $s.fb = $(genfunc(v))
            #@show "bisect: $($s.b) => $($s.fb)"
            @assert sign($s.fa) != sign($s.fb)
            $s.N = 1
            $s.c = ($s.a + $s.b) / 2
            $C.store!($s, $s.c)
            $s.step = :c
            @goto $lstart
        elseif $s.step == :c
            $s.fc = $(genfunc(v))
            #@show "bisect: $($s.c) => $($s.fc)"
            if $s.fc ≈ zero($s.fc) || ($s.b - $s.a) / $s.d < $TOL
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
