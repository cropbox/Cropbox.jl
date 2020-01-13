abstract type System end

name(s::S) where {S<:System} = string(S)
import Base: names
names(s::S) where {S<:System} = names(S)
names(S::Type{<:System}) = (n = split(String(Symbol(S)), "."); [Symbol(join(n[i:end], ".")) for i in 1:length(n)])

import Base: length, iterate, eltype
length(::System) = 1
iterate(s::System) = (s, nothing)
iterate(s::System, i) = nothing
eltype(::S) where {S<:System} = S

import Base: broadcastable
broadcastable(s::System) = Ref(s)

import Base: getindex
getindex(s::System, i) = getproperty(s, i)
getindex(s::System, ::Nothing) = s

import Base: getproperty
getproperty(s::System, n::String) = begin
    reduce((a, b) -> begin
        m = match(r"([^\[\]]+)(?:\[(.+)\])?", b)
        n, i = m[1], m[2]
        v = getfield(a, Symbol(n))
        v[i]
    end, [s, split(n, ".")...])
end

#HACK: swap out state variable of mutable System after initialization
setvar!(s::System, k::Symbol, v) = begin
    setfield!(s, k, v)
    a = Dict(fieldnamesalias(s))[k]
    !isnothing(a) && setfield!(s, a, v)
    nothing
end

import Base: show
show(io::IO, s::System) = print(io, "<$(name(s))>")

export System
