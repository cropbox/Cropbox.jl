struct Var{S<:State,V} <: AbstractVar
    system::System
    state::State{V}
    equation::Equation
    name::Symbol
    alias::Tuple{Vararg{Symbol}}

    Var(s::System, e::E, ::Type{S}; _name, _alias=(), _value, stargs...) where {S<:State,E<:Equation} = begin
        e = patch_config!(s, e, [_name, _alias...])
        v = ismissing(_value) ? value(e) : _value
        st = S(; _name=_name, _system=s, _value=v, stargs...)
        V = valuetype(st)
        e = patch_valuetype!(s, e, st)
        EE = typeof(e)
        N = Symbol("$(name(s))<$_name>")
        x = new{S,V}(s, st, e, _name, _alias)
    end
end

patch_config!(s::System, e::Equation, n) = begin
    c = s.context.config
    # patch state variable from config
    v = option(c, s, n)
    #HACK: avoid Dict used for partial argument patch
    if !isnothing(v) && !(isa(v, AbstractDict))
        Equation(v, e.name)
    else
        patch_config_args!(s, e, n)
    end
end
patch_config_args!(s::System, e::StaticEquation, n) = e
patch_config_args!(s::System, e::DynamicEquation, n) = begin
    c = s.context.config
    # patch default arguments from config
    d = e.default
    resolve!(a::Symbol) = begin
        override!(a::Symbol, v) = (d[a] = VarVal(s, v))

        # 1. external options (i.e. TOML config)
        v = option(c, s, n, a)
        !isnothing(v) && return override!(a, v)

        # 2. default parameter values
        v = get(d, a, missing)
        !ismissing(v) && return override!(a, v)
    end
    resolve!.(e.args.names)
    resolve!.(e.kwargs.names)
    e
end
patch_valuetype!(s::System, e::StaticEquation, st::State) = e
patch_valuetype!(s::System, e::DynamicEquation, st::State) = begin
    V = valuetype(st)
    Equation{V}(e.func, e.name, e.args, e.kwargs, e.default)
end

#TODO: incorporate patch_config_* here
patch_default!(s::System, x::Var, e::StaticEquation) = e
patch_default!(s::S, x::Var, e::DynamicEquation) where {S<:System} = begin
    d = e.default
    for ea in (e.args, e.kwargs)
        l = ea.tmpl
        for n in ea.names
            # # 2. default parameter values
            # v = get(d, n, missing)
            # if !ismissing(v)
            #     if isa(v, VarVal{Any})
            #         v = VarVal(v)
            #         d[n] = v
            #         #@show "overriden! d[$n] = $v"
            #     end
            #     l[n] = v
            #     continue
            # end

            # 3. state vars from current system
            #if !haskey(l, n) && hasfield(S, n)
            if hasfield(S, n)
                l[n] = getvar(s, n)
                continue
            end

            # 4. argument not found (partial function used by Call State)
            l[n] = missing
        end
    end
    # n = [x.name, x.alias...]
    #
    # c = s.context.config
    # # patch default arguments from config
    # resolve!(a::Symbol) = begin
    #     override!(a::Symbol, v::VarVal) = (e.default[a] = VarVal(v))
    #     override!(a::Symbol, v::Var) = nothing
    #     override!(a::Symbol, v) = (e.default[a] = VarVal(s, v))
    #
    #     # 1. external options (i.e. TOML config)
    #     v = option(c, s, n, a)
    #     !isnothing(v) && return override!(a, v)
    #
    #     # 2. default parameter values
    #     v = get(e.default, a, missing)
    #     !ismissing(v) && return override!(a, v)
    # end
    # resolve!.(argsname(e))
    # resolve!.(kwargsname(e))
    # e

    #@show e.default
end

name(x::Var) = x.name
import Base: names
names(x::Var) = [x.name, x.alias...]

system(x::Var) = x.system
state(x::Var{S,V}) where {S<:State,V} = x.state::S{V}
statetype(::Var{S,V}) where {S<:State,V} = S
valuetype(::Var{S,V}) where {S<:State,V} = V

(x::Var)() = handle(x, x.equation)

import DataStructures: OrderedDict
handle(x::Var, e::StaticEquation) = value(e)
handle(x::Var, e::DynamicEquation) = begin
    s = x.system
    # d = e.default
    # args = handle2!(x, s, e, d, argsname(e), e.largs)
    # kwargs = handle2!(x, s, e, d, kwargsname(e), e.lkwargs)
    args = handle2!(e.args, e.default)
    kwargs = handle2!(e.kwargs, e.default)
    handle3(x, args, kwargs)
end
#handle2!(x::Var, s::System, e::DynamicEquation, d, n, l) = begin
handle2!(ea::EquationArg, d) = begin
    l = ea.tmpl
    if !ea.overridden
        overriding = 0
        for n in ea.names
            # 2. default parameter values
            v = get(d, n, missing)
            if !ismissing(v)
                if isa(v, VarVal{Any})
                    v = VarVal(v)
                    d[n] = v
                    #@show "overriden! d[$n] = $v"
                    overriding += 1
                end
                l[n] = v
            end

            # # 4. argument not found (partial function used by Call State)
            # l[a] = missing
        end
        if overriding == 0
            #@show "overridden finish $ea"
            ea.overridden = true
        end
    end
    w = ea.work
    for (k, v) in l
        w[k] = value(v)
    end
    w
end

handle3(x::Var, args, kwargs) = handle4(x.equation, args, kwargs)
handle3(x::Var{Call}, args, kwargs) where V = function (pargs...; pkwargs...)
    # arg
    i = 1
    for (k, v) in args
        if ismissing(v)
            args[k] = pargs[i]
            i += 1
        end
    end
    @assert i-1 == length(pargs) "incorrect number of positional arguments: $pargs"
    # kwarg
    merge!(kwargs, pkwargs)
    handle4(x.equation, args, kwargs)
end

handle4(e::DynamicEquation, args, kwargs) = call(e, values(args)...; kwargs...)

getvar(x::Var) = x
getvar(x) = missing
getvar(s::System, n::Symbol) = getfield(s, n)
getvar(s::System, l::Vector) = begin
    #HACK: manual reduction due to memory allocations
    #reduce((a, b) -> getvar(a, b), [s; l])
    a = s
    for b in l
        a = getvar(a, b)
    end
    a
end
getvar(s::System, n::AbstractString) = getvar(varpath(s, n))

getvar(x::Var{Produce}, o::VarOpAll) = value(x)
getvar(x::Var{Produce}, o::VarOpRecursiveAll) = begin
    v = value(x)
    l = System[]
    #TODO: possibly reduce overhead by reusing calculated values in child nodes
    f(v) = (append!(l, v); foreach(s -> f.(value(s, x.name)), v); l)
    f(v)
end
getvar(v::Vector{<:System}, o::VarOpIndex) = begin
    n = length(v)
    i = o.index
    i = (i >= 0) ? i : n+i+1
    (1 <= i <= n) ? [v[i]] : System[]
end
getvar(v::Vector{<:System}, o::VarOpFilter) = filter(s -> value(s, Symbol(o.cond)), v)
getvar(s::Vector, n::Symbol) = getvar.(s, n)

pushvars!(X, x::Var) = push!(X, x)
pushvars!(X, x::Vector{<:Var}) = union!(X, x)
pushvars!(X, x) = nothing

getvars(x::Var, X) = (pushvars!(X, x); x)
getvars(x, X) = missing #FIXME: needed?
getvars(s::System, n::Symbol, X) = (x = getvar(s, n); pushvars!(X, x); x)
getvars(s::System, l::Vector, X) = reduce((a, b) -> getvars(a, b, X), [s, l...])
getvars(s::System, n::AbstractString, X) = getvars(varpath(s, n), X) #FIXME: needed?

getvars(x::Var{Produce}, o::VarOpAll, X) = (pushvars!(X, x); getvar(x, o))
getvars(x::Var{Produce}, o::VarOpRecursiveAll, X) = (pushvars!(X, x); getvar(x, o))
getvars(v::Vector{<:System}, o::VarOpIndex, X) = getvar(v, o)
getvars(v::Vector{<:System}, o::VarOpFilter, X) = begin
    vx = [getvar(s, Symbol(o.cond)) for s in v]
    foreach(x -> pushvars!(X, x), vx)
    getvar(v, o)
end
getvars(s::Vector, n::Symbol, X) = (x = getvar.(s, n); pushvars!(X, x); x)

value(x::Var{S,V}) where {S<:State,V} = value(state(x))#::V
value(x::Var{Call,V}) where V = value(state(x))#::Union{Function,Missing}
value(x::Var{Produce,V}) where V = value(state(x))#::Vector{V}
value(x) = x
#FIXME: do we really need getindex here?
#value(s::System, n) = s[n]
value(s::System, n) = value(getvar(s, n))
value(x::Vector{<:Var}) = value.(x)

priority(::Type{Var{S}}) where {S<:State} = priority(S)

advance!(x::Var{Advance}) = advance!(state(x))
reset!(x::Var{Advance}) = reset!(state(x))

import Base: convert, promote_rule
convert(::Type{System}, x::Var) = x.system
convert(::Type{Vector{Symbol}}, x::Var) = [x.name]
convert(::Type{X}, x::Var) where {X<:Var} = x
convert(::Type{V}, x::Var) where {V<:Number} = convert(V, value(x))
promote_rule(::Type{X}, ::Type{V}) where {X<:Var, V<:Number} = V
promote_rule(::Type{Bool}, ::Type{X}) where {X<:Var} = Bool

import Base: ==, isless
#HACK: would make different Vars with same internal value clash for Dict key
# ==(a::Var, b::Var) = ==(value(a), value(b))
==(a::Var, b::V) where {V<:Number} = ==(promote(a, b)...)
==(a::V, b::Var) where {V<:Number} = ==(b, a)
#TODO: reduce redundant declarations of basic functions (i.e. comparison)
isless(a::Var, b::Var) = isless(value(a), value(b))
isless(a::Var, b::V) where {V<:Number} = isless(promote(a, b)...)
isless(a::V, b::Var) where {V<:Number} = isless(b, a)

import Base: getindex, length, iterate
getindex(x::Var, i::Integer) = getindex(state(x), i)
length(x::Var) = length(state(x))
iterate(x::Var) = iterate(state(x))
iterate(x::Var, i) = iterate(state(x), i)

import Base: show
show(io::IO, x::Var) = print(io, "$(name(x.system))<$(name(x))> = $(state(x))")

export value
