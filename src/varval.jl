struct VarPath
    system::System
    path::Vector{Symbol}
end

import Base: convert
convert(::Type{Vector{Symbol}}, s::Symbol) = [s]
convert(::Type{Vector{Symbol}}, s::String) = Symbol.(split(s, "."))

VarPath(s::System, n...) = VarPath(s, convert.(Vector{Symbol}, n) |> Iterators.flatten |> collect)
VarPath(n...) = VarPath(convert(System, n[1]), n[2:end]...)
convert(::Type{VarPath}, n) = VarPath(n...)
convert(::Type{VarPath}, n::VarPath) = n

getvar(p::VarPath) = reduce((a, b) -> getfield(a, b), [p.system; p.path])
value!(p::VarPath) = value!(getvar(p))

convert(::Type{V}, p::VarPath) where {V<:Number} = convert(V, value!(p))
convert(::Type{V}, p::VarPath) where {V<:Quantity} = convert(V, unitfy(value!(p), unit(V)))

struct VarVal{V<:Number}
    v::Union{VarPath,V}
end

VarVal{V}(s::System, p::Union{Symbol,String}) where {V<:Number} = VarVal{V}(VarPath(s, p))
VarVal{V}(s::System, p) where {V<:Number} = VarVal{V}(convert(V, p))
VarVal{V}(s::System, p) where {V<:Quantity} = VarVal{V}(convert(V, unitfy(p, unit(V))))

value!(v::VarVal) = value!(v.v)

convert(::Type{VarVal{V}}, v) where {V<:Number} = VarVal{V}(convert(V, v))
convert(::Type{VarVal{V}}, v::VarVal) where {V<:Number} = v
convert(::Type{V}, v::VarVal) where V = convert(V, v.v)

import Base: promote_rule
promote_rule(::Type{T}, ::Type{VarVal}) where {T<:Number} = T
