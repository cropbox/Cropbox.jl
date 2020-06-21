mutable struct Advance{T} <: State{T}
    t::T
    Δt::T
end

Advance(; init=nothing, step=nothing, unit, _type, _...) = begin
    T = valuetype(_type, value(unit))
    t = isnothing(init) ? zero(T) : value(init)
    Δt = isnothing(step) ? oneunit(T) : value(step)
    #T = promote_type(typeof(t), typeof(Δt))
    Advance{T}(t, Δt)
end

value(s::Advance) = s.t
advance!(s::Advance) = s.t += s.Δt

genvartype(v::VarInfo, ::Val{:Advance}; V, _...) = @q Advance{$V}

geninit(v::VarInfo, ::Val{:Advance}) = missing

genupdate(v::VarInfo, ::Val{:Advance}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $C.advance!($s)
    end
end
