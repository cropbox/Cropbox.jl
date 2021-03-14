mutable struct Advance{T} <: State{T}
    value::T
    t::T
    Δt::T
end

Advance(; init=nothing, step=nothing, unit, _type, _...) = begin
    U = value(unit)
    T = valuetype(_type, U)
    t = isnothing(init) ? zero(T) : unitfy(value(init), U)
    Δt = isnothing(step) ? oneunit(T) : unitfy(value(step), U)
    #T = promote_type(typeof(t), typeof(Δt))
    Advance{T}(t, t, Δt)
end

constructortags(::Val{:Advance}) = (:init, :step, :unit)

genvartype(v::VarInfo, ::Val{:Advance}; V, _...) = @q Advance{$V}

geninit(v::VarInfo, ::Val{:Advance}) = missing

genupdate(v::VarInfo, ::Val{:Advance}, ::MainStep) = begin
    @gensym s t
    @q let $s = $(symstate(v)),
           $t = $s.t
        $s.t += $s.Δt
        $C.store!($s, $t)
    end
end
