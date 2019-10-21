mutable struct Solve{V} <: State{V}
    value::V
    lower::V
    upper::V
    step::Symbol
    N::Int
    a::V
    b::V
    c::V
    fa::V
    fb::V
    fc::V
end

Solve(; lower=nothing, upper=nothing, unit, _type, _...) = begin
    V = valuetype(_type, value(unit))
    v = zero(V)
    Solve{V}(v, lower, upper, :z, 0, v, v, v, v, v, v)
end
