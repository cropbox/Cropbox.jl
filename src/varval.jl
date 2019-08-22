struct VarPath
    system::System
    path::Vector{Symbol}
end

import Base: convert
convert(::Type{Vector{Symbol}}, s::Symbol) = [s]
convert(::Type{Vector{Symbol}}, s::String) = Symbol.(split(s, "."))

VarPath(s::System, p::Vector) where V = VarPath(s, convert.(Vector{Symbol}, p) |> Iterators.flatten |> collect)

getvar(p::VarPath) = reduce((a, b) -> getfield(a, b), [p.system; p.path])
value(p::VarPath) = value(getvar(p))
value!(p::VarPath) = value!(getvar(p))

convert(::Type{V}, p::VarPath) where {V<:Number} = convert(V, value!(p))
convert(::Type{V}, p::VarPath) where {V<:Quantity} = convert(V, unitfy(value!(p), unit(V)))

struct VarVal{V<:Number}
    v::Union{VarPath,V}
end

VarVal{V}(s::System, p::String) where {V<:Number} = VarVal{V}(VarPath(s, p))
VarVal{V}(s::System, p::String) where {V<:Quantity} = VarVal{V}(VarPath(s, p))
VarVal{V}(s::System, p) where {V<:Number} = VarVal{V}(convert(V, p))
VarVal{V}(s::System, p) where {V<:Quantity} = VarVal{V}(convert(V, unitfy(p, unit(V))))
VarVal{V}(s::System, ::Nothing) where {V<:Number} = nothing
VarVal{V}(s::System, ::Nothing) where {V<:Quantity} = nothing

value(v::VarVal) = value(v.v)
value!(v::VarVal) = value!(v.v)
