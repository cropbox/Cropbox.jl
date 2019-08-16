mutable struct Var{S<:State}
    system::System
    equation::Equation
    name::Symbol
    alias::Vector{Symbol}
    state::S

    Var(s, e, ::Type{S}; _name, _alias=Symbol[], stargs...) where {S<:State} = begin
        x = new{S}(s, e, _name, _alias)
        x.state = S(; _system=s, _var=x, prepare(stargs)...)
        init!(x)
    end
end

prepare(stargs...) = begin
    d = Dict{Symbol,Any}(stargs...)
    #TODO: maybe better use u_str as is, instead allow implicit "unit=" in the macro
    if haskey(d, :unit)
        d[:unit] = unitstr(d[:unit])
    end
    d
end

init!(x::Var) = begin
    s = x.system
    e = x.equation
    c = s.context.config
    # patch default arguments from config
    resolve(a::Symbol) = begin
        # 1. external options (i.e. TOML config)
        v = option(c, s, x, a)
        !isnothing(v) && (e.default[a] = v)
    end
    resolve.(e.args)
    # patch state variable from config
    v = option(c, s, x)
    #HACK: avoid Dict used for partial argument patch
    if !isnothing(v) && !(typeof(v) <: Dict)
        x.equation = Equation(() -> v, e.name, [], [], Dict())
    end
    x
end

import Base: names
names(x::Var) = [[x.name]; x.alias]

(x::Var)() = begin
    s = x.system
    #TODO: use var path exclusive str (i.e. v_str)
    #TODO: unit handling (i.e. u_str)
    interpret(v::Symbol) = value!(s, v)
    interpret(v::String) = value!(s, v)
    interpret(v) = v
    resolve(a::Symbol) = begin
        # 2. default parameter values
        v = get(x.equation.default, a, nothing)
        !isnothing(v) && return interpret(v)

        # 3. state vars from current system
        isdefined(s, a) && return interpret(a)

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
advance!(x::Var) = advance!(x.state)
reset!(x::Var) = reset!(x.state)
update!(x::Var) = queue!(x.system.context, store!(x.state, () -> x()), priority(x.state))

import Base: convert, promote_rule
convert(T::Type{System}, x::Var) = x.system
convert(::Type{Vector{Symbol}}, x::Var) = [x.name]
convert(T::Type{X}, x::Var) where {X<:Var} = x
convert(T::Type{V}, x::Var) where {V<:Number} = convert(T, value!(x))
promote_rule(::Type{X}, T::Type{V}) where {X<:Var, V<:Number} = T
promote_rule(T::Type{Bool}, ::Type{X}) where {X<:Var} = T

import Base: ==, isless
==(a::Var, b::Var) = ==(value!(a), value!(b))
==(a::Var, b::V) where {V<:Number} = ==(promote(a, b)...)
==(a::V, b::Var) where {V<:Number} = ==(b, a)
#TODO: reduce redundant declarations of basic functions (i.e. comparison)
isless(a::Var, b::Var) = isless(value!(a), value!(b))
isless(a::Var, b::V) where {V<:Number} = isless(promote(a, b)...)
isless(a::V, b::Var) where {V<:Number} = isless(b, a)

import Base: getindex, length, iterate
getindex(x::Var, i::Integer) = getindex(x.state, i)
length(x::Var) = length(x.state)
iterate(x::Var) = iterate(x.state)
iterate(x::Var, i) = iterate(x.state, i)

import Base: show
show(io::IO, x::Var) = print(io, "$(x.system)<$(x.name)> = $(x.state.value)")

export Var, value!
