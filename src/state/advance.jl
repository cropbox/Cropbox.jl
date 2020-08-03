mutable struct Advance{T} <: State{T}
    t::T
    Δt::T
    Δ::T
end

Advance(; init=nothing, step=nothing, unit, _type, _...) = begin
    T = valuetype(_type, value(unit))
    t = isnothing(init) ? zero(T) : value(init)
    #HACK: ensure initial update! not increase tick already
    Δt = zero(T)
    Δ = isnothing(step) ? oneunit(T) : value(step)
    #T = promote_type(typeof(t), typeof(Δt))
    Advance{T}(t, Δt, Δ)
end

constructortags(::Val{:Advance}) = (:init, :step, :unit)

value(s::Advance) = s.t
advance!(s::Advance) = begin
    s.t += s.Δt
    s.Δt = s.Δ
end

genvartype(v::VarInfo, ::Val{:Advance}; V, _...) = @q Advance{$V}

geninit(v::VarInfo, ::Val{:Advance}) = missing

genupdate(v::VarInfo, ::Val{:Advance}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $C.advance!($s)
    end
end
