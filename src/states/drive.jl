mutable struct Drive{V} <: State{V}
    value::V
end

Drive(; unit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    V = promote_type(V, typeof(v))
    Drive{V}(v)
end
