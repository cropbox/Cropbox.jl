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

convert(T::Type{V}, p::VarPath) where {V<:Number} = convert(T, value!(p))
convert(T::Type{Q}, p::VarPath) where {Q<:Quantity} = uconvert(unit(T), value!(p))

const VarVal = Union{VarPath,V} where {V<:Number}

VarVal(s::System, p::Union{Symbol,String}) = VarPath(s, p)
VarVal(s::System, p::V) where {V<:Number} = p
VarVal{V}(s::System, p::Union{Symbol,String}) where {V<:Number} = VarVal(s, p)
VarVal{V}(s::System, p) where {V<:Number} = convert(V, p)
VarVal{Q}(s::System, p::R) where {Q<:Quantity,R<:Number} = Quantity(p, unit(Q))
VarVal{Q}(s::System, p::R) where {Q<:Quantity,R<:Quantity} = uconvert(unit(Q), p)
VarVal(s::System, p) = p

convert(::Type{VarVal{V}}, v) where {V<:Number} = convert(V, v)
convert(::Type{VarVal{V}}, v::VarVal{V}) where {V<:Number} = v
