mutable struct Var{S<:State} <: Number
    system::System
    equation::Equation
    name::Symbol
    alias::Union{Symbol,Nothing}
    state::S

    Var(s, e, ST::Type{S}; name, alias=nothing, stargs...) where {S<:State} = begin
        v = new{S}(s, e, name, alias)
        v.state = S(; system=s, var=v, stargs...)
        v
    end
end

import Base: names
names(x::Var) = filter(!isnothing, [x.name, x.alias])

(x::Var)() = begin
    s = x.system
    #TODO: use var path exclusive str (i.e. v_str)
    #TODO: unit handling (i.e. u_str)
    interpret(v::String) = getvar(s, v)
    interpret(v) = v
    resolve(a::Symbol) = begin
        # 1. external options (i.e. TOML config)
        v = option(s.context, s, x, a)
        !isnothing(v) && return interpret(v)

        # 2. default parameter values
        v = get(x.equation.default, a, nothing)
        !isnothing(v) && return interpret(v)

        # 3. state vars from current system
        isdefined(s, a) && return value!(s, a)

        # 4. argument not found (partial function)
        nothing
    end
    args = resolve.(x.equation.args)
    kwargs = resolve.(x.equation.kwargs)
    if length(args) == length(x.equation.args) && length(kwargs) == length(x.equation.kwargs)
        x.equation(args...; kwargs...)
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
            x.equation(args...; kwargs...)
        end
    end
end

getvar(s::System, n::Symbol) = getfield(s, n)
getvar(s::System, n::String) = reduce((a, b) -> getfield(a, b), [s; Symbol.(split(n, "."))])

value!(x::Var) = (check!(x.state) && update!(x); value(x.state))
value!(x) = x
value!(s::System, n) = value!(getvar(s, n))
update!(x::Var) = begin
    f = () -> x()
    store!(x.state, f)
    ps = poststore!(x.state, f)
    !isnothing(ps) && queue!(x.system.context, ps, priority(x.state))
end

import Base: convert, promote_rule
convert(T::Type{System}, x::Var) = x.system
convert(::Type{Vector{Symbol}}, x::Var) = [x.name]
convert(T::Type{X}, x::Var) where {X<:Var} = x
convert(T::Type{V}, x::Var) where {V<:Number} = convert(T, value!(x))
promote_rule(::Type{X}, T::Type{V}) where {X<:Var, V<:Number} = T
promote_rule(T::Type{Bool}, ::Type{X}) where {X<:Var} = T

import Base: ==
==(a::Var, b::Var) = (value(a.state) == value(b.state))

import Base: show
show(io::IO, x::Var) = print(io, "$(x.system)<$(x.name)> = $(x.state.value)")

export System, Var, value!, update!
