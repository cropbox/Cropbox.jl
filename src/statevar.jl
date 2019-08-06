mutable struct Statevar{S<:State} <: Number
    system::System
    equation::Equation
    state::S

    name::Symbol
    alias::Union{Symbol,Nothing}
    time::StatevarPath

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
inittime!(s::Statevar, st::State; time, stargs...) = (s.time = (s, time))
inittime!(s::Statevar, st::Tock; stargs...) = (s.time = (s, s))

import Base: names
names(s::Statevar) = filter(!isnothing, [s.name, s.alias])

(s::Statevar)() = begin
    #TODO: use var path exclusive str (i.e. v_str)
    #TODO: unit handling (i.e. u_str)
    interpret(a::String) = getvar(s.system, a)
    interpret(a) = a
    resolve(a::Symbol) = begin
        # 1. external options (i.e. TOML config)
        v = option(s.system.context, s.system, s, a)
        !isnothing(v) && return interpret(v)

        # 2. default parameter values
        v = get(s.equation.default, a, nothing)
        !isnothing(v) && return interpret(v)

        # 3. statevars from current system
        isdefined(s.system, a) && return getvar!(s.system, a)

        # 4. argument not found (partial function)
        nothing
    end
    args = resolve.(s.equation.args)
    kwargs = resolve.(s.equation.kwargs)
    if length(args) == length(s.equation.args) && length(kwargs) == length(s.equation.kwargs)
        s.equation(args...; kwargs...)
    else
        function (pargs...; pkwargs...)
            for a in pargs
                #replace(x -> isnothing(x) ? a : x, args; count=1)
                i = findfirst(isnothing, args)
                @assert !isnothing(i)
                args[i] = a
            end
            @assert findfirst(isnothing, args) |> isnothing
            kwargs = merge(kwargs, pkwargs)
            s.equation(args...; kwargs...)
        end
    end
end

checker!(s::Statevar{Tock}) = value(getvar(s.time).state)
checker!(s::Statevar) = getvar!(s.time)

getvar(s::System, n::Symbol) = getfield(s, n)
getvar(s::System, n::String) = reduce((a, b) -> getfield(a, b), [s; Symbol.(split(n, "."))])

getvar!(s::Statevar) = (check!(s.state, checker!(s)...) && setvar!(s); value(s.state))
getvar!(s::System, n) = getvar!(getvar(s, n))
setvar!(s::Statevar) = begin
    f = () -> s()
    store!(s.state, f)
    ps = poststore!(s.state, f)
    !isnothing(ps) && queue!(s.system.context, ps, priority(s.state))
end

import Base: convert, promote_rule
convert(T::Type{System}, s::Statevar) = s.system
convert(::Type{Vector{Symbol}}, s::Statevar) = [s.name]
convert(T::Type{S}, s::Statevar) where {S<:Statevar} = s
convert(T::Type{V}, s::Statevar) where {V<:Number} = convert(T, getvar!(s))
promote_rule(::Type{S}, T::Type{V}) where {S<:Statevar, V<:Number} = T

import Base: ==
==(s1::Statevar, s2::Statevar) = (value(s1.state) == value(s2.state))

import Base: show
show(io::IO, s::Statevar) = print(io, "$(s.system)<$(s.name)> = $(s.state.value)")

export System, Statevar, getvar!, setvar!
