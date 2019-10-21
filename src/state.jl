abstract type State{V} end

#TODO: support call syntax in Julia 1.3
#(s::State)() = value(s)

value(v) = v
value(s::State) = s.value
value(S::Vector{<:State}) = value.(S)

import Base: adjoint
adjoint(s::State) = value(s)

store!(s::State, v) = (s.value = unitfy(v, unit(s)))

import Base: getindex, length, iterate
getindex(s::State, i) = s
length(s::State) = 1
iterate(s::State) = (s, nothing)
iterate(s::State, i) = nothing

import Unitful: unit
unit(::State{V}) where V = unittype(V)
unittype(V) = ((V <: Quantity) ? unit(V) : nothing)

import Unitful: Units, dimension
valuetype(::State{V}) where V = V
valuetype(T, ::Nothing) = T
valuetype(T, U::UU) where {UU<:Units} = Quantity{T, dimension(U), UU}
valuetype(::Type{Array{T,N}}, U::Units) where {T,N} = Array{valuetype(T, U), N}

rateunittype(U::Nothing, T::Units) = T^-1
rateunittype(U::Units, T::Units) = U/T
rateunittype(U::Units, T::Nothing) = U
rateunittype(U::Nothing, T::Nothing) = nothing

abstract type Priority end
struct PrePriority <: Priority end
struct PostPriority <: Priority end

priority(::S) where {S<:State} = priority(S)
priority(::Type{<:State}) = PostPriority()

import Base: convert, promote_rule
convert(::Type{<:State}, s::State) = s
convert(::Type{V}, s::State) where V = convert(V, value(s))
promote_rule(::Type{<:State}, ::Type{V}) where V = V

import Base: ==
#HACK: would make different Vars with same internal value clash for Dict key
# ==(a::State, b::State) = ==(value(a), value(b))
==(a::State, b::V) where V = ==(promote(a, b)...)
==(a::V, b::State) where V = ==(b, a)
#TODO: reduce redundant declarations of basic functions (i.e. comparison)
# import Base: isless
# isless(a::State, b::State) = isless(value(a), value(b))
# isless(a::State, b::V) where {V<:Number} = isless(promote(a, b)...)
# isless(a::V, b::State) where {V<:Number} = isless(b, a)

import Base: show
show(io::IO, s::S) where {S<:State} = begin
    v = value(s)
    r = isnothing(v) ? repr(v) : string(v)
    r = length(r) > 40 ? "<..>" : r
    print(io, r)
end

include("states/hold.jl")
include("states/wrap.jl")
include("states/advance.jl")
include("states/preserve.jl")
include("states/tabulate.jl")
include("states/interpolate.jl")
include("states/track.jl")
include("states/drive.jl")
include("states/call.jl")
include("states/accumulate.jl")
include("states/capture.jl")
include("states/flag.jl")
include("states/produce.jl")
include("states/solve.jl")
