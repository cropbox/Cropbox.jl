struct Preserve{V} <: State{V}
    value::V
end

# Preserve is the only State that can store value `nothing`
Preserve(; unit, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    V = promote_type(V, typeof(v))
    Preserve{V}(v)
end

genvartype(v::VarInfo, ::Val{:Preserve}; V, _...) = @q Preserve{$V}

geninit(v::VarInfo, ::Val{:Preserve}) = geninitpreserve(v)

genupdate(v::VarInfo, ::Val{:Preserve}, ::MainStep) = genvalue(v)
