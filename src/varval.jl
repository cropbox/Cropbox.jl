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
const VarVal = Union{VarPath,V} where V

VarVal(s::System, p::Symbol) = VarPath(s, p)
VarVal(s::System, p::String) = VarPath(s, p)
VarVal(s::System, p) = p
