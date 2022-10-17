abstract type State{V} end

#TODO: support call syntax in Julia 1.3
#(s::State)() = value(s)

value(v) = v
value(s::State) = getfield(s, :value)
value(S::Vector{<:State}) = value.(S)

export value

Base.getindex(s::State) = value(s)
Base.adjoint(s::State) = value(s)

store!(s::State, v) = setfield!(s, :value, convert(valuetype(s), unitfy(v, unittype(s))))

Base.getindex(s::State, i) = value(s)[i]
Base.length(s::State) = 1
Base.iterate(s::State) = (s, nothing)
Base.iterate(s::State, i) = nothing
Base.eltype(::Type{<:State{V}}) where V = V

unittype(::Type{V}) where V = nothing
unittype(::Type{V}) where {V<:Number} = Unitful.unit(V)
unittype(::Type{<:State{V}}) where V = unittype(V)
unittype(::Type{<:Vector{V}}) where V = unittype(V)
unittype(::Type{<:Vector{Union{V,Missing}}}) where V = unittype(V)
unittype(::Type{<:AbstractRange{V}}) where V = unittype(V)
unittype(::T) where T = unittype(T)
unittype(v::DataFrame) = unittype.(eltype.(eachcol(v)))

valuetype(::State{V}) where V = V
valuetype(T, ::Nothing) = T
valuetype(T, U::Units) = Unitful.isunitless(U) ? T : Quantity{T, Unitful.dimension(U), typeof(U)}
valuetype(::Type{Array{T,N}}, U::Units) where {T,N} = Array{valuetype(T, U), N}

rateunittype(U::Nothing, T::Units) = T^-1
rateunittype(U::Units, T::Units) = (R = U/T; Unitful.isunitless(R) ? nothing : R)
rateunittype(U::Units, T::Nothing) = U
rateunittype(U::Nothing, T::Nothing) = nothing

timeunittype(U, TU=u"hr") = isnothing(U) ? TU : (Unitful.dimension(U) == Unitful.𝐓) ? U : TU

struct Nounit{S,U}
    state::S
    unit::U
end

nounit(s::State, u::Units) = Nounit(s, u)
nounit(s::State) = Nounit(s, missing)
value(s::Nounit) = deunitfy(value(s.state), s.unit)

export nounit

struct Not{S}
    state::S
end

Base.:!(s::State) = Not(s)
value(s::Not) = !value(s.state)

struct And{S1,S2}
    state1::S1
    state2::S2
end

struct Or{S1,S2}
    state1::S1
    state2::S2
end

Base.:&(a::Union{State,And,Or,Not}, b::Union{State,And,Or,Not}) = And(a, b)
Base.:|(a::Union{State,And,Or,Not}, b::Union{State,And,Or,Not}) = Or(a, b)
value(s::And) = value(s.state1) && value(s.state2)
value(s::Or) = value(s.state1) || value(s.state2)

mutable struct StateRef{V,S<:State{V}} <: State{V}
    state::S
end

Base.getindex(r::StateRef) = r.state
value(r::StateRef) = value(r[])
setvalue!(r::StateRef, s::State) = (r.state = s)

#HACK: swap out state variable of mutable System after initialization
setvar!(s::System, k::Symbol, v::State) = begin
    r = s[k]
    @assert r isa StateRef
    setvalue!(r, v)
    a = Dict(fieldnamesalias(s))[k]
    !isnothing(a) && setvalue!(s[a], v)
    nothing
end

abstract type Priority end
struct PrePriority <: Priority end
struct PostPriority <: Priority end

priority(::S) where {S<:State} = priority(S)
priority(::Type{<:State}) = PostPriority()

Base.show(io::IO, s::State) = begin
    v = value(s)
    maxlength = get(io, :maxlength, nothing)
    r = labelstring(v; maxlength)
    print(io, r)
end
Base.show(io::IO, ::MIME"text/plain", s::State) = print(io, value(s))

include("state/hold.jl")
include("state/bring.jl")
include("state/wrap.jl")
include("state/advance.jl")
include("state/preserve.jl")
include("state/tabulate.jl")
include("state/interpolate.jl")
include("state/track.jl")
include("state/remember.jl")
include("state/provide.jl")
include("state/drive.jl")
include("state/call.jl")
include("state/integrate.jl")
include("state/accumulate.jl")
include("state/capture.jl")
include("state/flag.jl")
include("state/produce.jl")
include("state/bisect.jl")
include("state/solve.jl")
