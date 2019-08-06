struct StatevarPath
    system::System
    path::Vector{Symbol}
end

import Base: convert
convert(::Type{Vector{Symbol}}, s::Symbol) = [s]
convert(::Type{Vector{Symbol}}, s::String) = Symbol.(split(s, "."))

StatevarPath(s::System, n...) = StatevarPath(s, convert.(Vector{Symbol}, n) |> Iterators.flatten |> collect)
StatevarPath(n...) = StatevarPath(convert(System, n[1]), n[2:end]...)
convert(::Type{StatevarPath}, n) = StatevarPath(n...)

getvar(s::StatevarPath) = reduce((a, b) -> getfield(a, b), [s.system; s.path])
getvar!(s::StatevarPath) = getvar!(getvar(s))
