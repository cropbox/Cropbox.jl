struct Preserve{V} <: State{V}
    value::V
end

# Preserve is the only State that can store value `nothing`
Preserve(; unit, optional, _value, _type, _...) = begin
    U = value(unit)
    V = valuetype(_type, U)
    v = _value
    #V = promote_type(V, typeof(v))
    V = optional ? Union{V,Nothing} : V
    Preserve{V}(v)
end

supportedtags(::Val{:Preserve}) = (:unit, :optional, :parameter, :override, :extern, :ref, :min, :max, :round)
constructortags(::Val{:Preserve}) = (:unit, :optional)

updatetags!(d, ::Val{:Preserve}; _...) = begin
    !haskey(d, :optional) && (d[:optional] = false)
end

genvartype(v::VarInfo, ::Val{:Preserve}; V, _...) = begin
    if istag(v, :optional)
        V = @q Union{$V,Nothing}
    end
    @q Preserve{$V}
end

gendefault(v::VarInfo, ::Val{:Preserve}) = gendefaultvalue(v, parameter=true)

genupdate(v::VarInfo, ::Val{:Preserve}, ::MainStep; kw...) = nothing
