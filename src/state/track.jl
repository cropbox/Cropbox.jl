mutable struct Track{V} <: State{V}
    value::V
end

Track(; unit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    #V = promote_type(V, typeof(v))
    Track{V}(v)
end

genvartype(v::VarInfo, ::Val{:Track}; V, _...) = @q Track{$V}
