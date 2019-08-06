mutable struct Statevar{S<:State} <: Number
    system::System
    equation::Equation
    name::Symbol
    alias::Union{Symbol,Nothing}
    state::S

    Statevar(sy, e, ST::Type{S}; name, alias=nothing, stargs...) where {S<:State} = begin
        s = new{S}(sy, e, name, alias)
        s.state = S(; system=sy, statevar=s, stargs...)
        s
    end
end

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

getvar(s::System, n::Symbol) = getfield(s, n)
getvar(s::System, n::String) = reduce((a, b) -> getfield(a, b), [s; Symbol.(split(n, "."))])

getvar!(s::Statevar) = (check!(s.state) && setvar!(s); value(s.state))
getvar!(s) = s
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
promote_rule(T::Type{Bool}, ::Type{S}) where {S<:Statevar} = T

import Base: ==
==(s1::Statevar, s2::Statevar) = (value(s1.state) == value(s2.state))

import Base: show
show(io::IO, s::Statevar) = print(io, "$(s.system)<$(s.name)> = $(s.state.value)")

export System, Statevar, getvar!, setvar!
