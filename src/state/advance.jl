mutable struct Advance{T} <: State{T}
    value::Timepiece{T}
end

Advance(; init=nothing, step=nothing, unit, _type, _...) = begin
    T = valuetype(_type, value(unit))
    t = isnothing(init) ? zero(T) : value(init)
    dt = isnothing(step) ? oneunit(T) : value(step)
    #T = promote_type(typeof(t), typeof(dt))
    Advance{T}(Timepiece{T}(t - dt, dt))
end

value(s::Advance) = s.value.t
advance!(s::Advance) = advance!(s.value)
reset!(s::Advance) = reset!(s.value)

genvartype(v::VarInfo, ::Val{:Advance}; V, _...) = @q Advance{$V}

geninit(v::VarInfo, ::Val{:Advance}) = missing

genupdate(v::VarInfo, ::Val{:Advance}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $C.advance!($s)
    end
end
