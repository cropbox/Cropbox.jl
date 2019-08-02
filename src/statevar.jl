mutable struct Statevar{S<:State} <: Number
    system::System
    equation::Equation
    state::S

    name::Symbol
    alias::Union{Symbol,Nothing}
    time::Statevar

    Statevar(sy, e, ST::Type{S}; stargs...) where {S<:State} = begin
        st = S(; stargs...)
        s = new{S}(sy, e, st)
        init!(s, st; stargs...)
    end
end

init!(s, st; stargs...) = begin
    initname!(s, st; stargs...)
    inittime!(s, st; stargs...)
    s
end
initname!(s::Statevar, st::State; name, alias=nothing, stargs...) = (s.name = name; s.alias = alias)
inittime!(s::Statevar, st::State; time, stargs...) = (s.time = time)
inittime!(s::Statevar, st::Tock; stargs...) = (s.time = s)

(s::Statevar)(args...; kwargs...) = s.equation(args...; kwargs...)

gettime!(s::Statevar{Tock}) = value(s.time.state)
gettime!(s::Statevar) = getvar!(s.time)

getvar!(s::Statevar) = begin
    t = gettime!(s)
    check!(s.state, t) && setvar!(s)
    value(s.state)
end
getvar!(s::System, n::Symbol) = getvar!(getfield(s, n))
setvar!(s::Statevar) = begin
    f = () -> s([getvar!(s.system, n) for n in s.equation.args]...)
    store!(s.state, f)
    ps = poststore!(s.state, f)
    !isnothing(ps) && queue!(s.system.context, ps, priority(s.state))
end

import Base: convert, promote_rule
convert(T::Type{S}, s::Statevar) where {S<:Statevar} = s
convert(T::Type{V}, s::Statevar) where {V<:Number} = convert(T, getvar!(s))
promote_rule(::Type{S}, T::Type{V}) where {S<:Statevar, V<:Number} = T

import Base: ==
==(s1::Statevar, s2::Statevar) = (value(s1.state) == value(s2.state))

import Base: show
show(io::IO, s::Statevar) = print(io, "$(s.system)<$(s.name)> = $(s.state.value)")

export System, Statevar, getvar!, setvar!
