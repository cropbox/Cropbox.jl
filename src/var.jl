struct Var{S<:State,V} <: AbstractVar
    system::System
    state::State{V}
    equation::Equation
    name::Symbol
    alias::Tuple{Vararg{Symbol}}
    nounit::Tuple{Vararg{Symbol}}

    Var(s::System, e::E, ::Type{S}; _name, _alias=(), _value, nounit="", stargs...) where {S<:State,E<:Equation} = begin
        e = patch_default!(s, e, [_name, _alias...])
        v = ismissing(_value) ? value(e) : _value
        st = S(; _name=_name, _system=s, _value=v, stargs...)
        nu = Tuple(Symbol.(split(nounit, ","; keepempty=false)))
        V = valuetype(st)
        e = patch_valuetype!(s, e, st)
        EE = typeof(e)
        N = Symbol("$(name(s))<$_name>")
        x = new{S,V}(s, st, e, _name, _alias, nu)
    end
end

patch_default!(s::System, e::Equation, n) = begin
    c = s.context.config
    # patch state variable from config
    v = option(c, s, n)
    #HACK: avoid Dict used for partial argument patch
    if !isnothing(v) && !(typeof(v) <: Dict)
        Equation(v, e.name)
    else
        patch_default_args!(s, e, n)
    end
end
patch_default_args!(s::System, e::StaticEquation, n) = e
patch_default_args!(s::System, e::DynamicEquation, n) = begin
    c = s.context.config
    # patch default arguments from config
    resolve!(a::Symbol) = begin
        override!(a::Symbol, v) = (default(e)[a] = VarVal(s, v))

        # 1. external options (i.e. TOML config)
        v = option(c, s, n, a)
        !isnothing(v) && return override!(a, v)

        # 2. default parameter values
        v = get(default(e), a, missing)
        !ismissing(v) && return override!(a, v)
    end
    resolve!.(argsname(e))
    resolve!.(kwargsname(e))
    e
end
patch_valuetype!(s::System, e::StaticEquation, st::State) = e
patch_valuetype!(s::System, e::DynamicEquation, st::State) = begin
    V = valuetype(st)
    Equation{V}(e.func, e.name, e.args, e.kwargs, e.default)
end

name(x::Var) = x.name
import Base: names
names(x::Var) = [x.name, x.alias...]

system(x::Var) = x.system
state(x::Var{S,V}) where {S<:State,V} = x.state::S{V}

(x::Var)() = handle(x, x.equation)

import DataStructures: OrderedDict
handle(x::Var, e::StaticEquation) = value(e)
handle(x::Var, e::DynamicEquation) = begin
    s = x.system
    d = default(e)
    args = handle(x, s, d, argsname(e); container=OrderedDict)
    kwargs = handle(x, s, d, kwargsname(e))
    handle(x, args, kwargs)
end
handle(x::Var, s::System, d, n; container=Dict) = begin
    resolve!(a::Symbol) = begin
        interpret(v::Symbol) = value!(s, v)
        interpret(v::VarVal) = value!(v)
        interpret(v) = v

        # 2. default parameter values
        v = get(d, a, missing)
        !ismissing(v) && return interpret(v)

        # 3. state vars from current system
        isdefined(s, a) && return interpret(a)

        # 4. argument not found (partial function used by Call State)
        missing
    end
    l = container{Symbol,Any}()
    for a in n
        l[a] = resolve!(a)
    end
    l
end

handle(x::Var, args, kwargs) = handle(x.equation, x.nounit, args, kwargs)
handle(x::Var{Call}, args, kwargs) = function (pargs...; pkwargs...)
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
    handle(x.equation, x.nounit, args, kwargs)
end

handle(e::DynamicEquation, nounit, args, kwargs) = begin
    process!(d) = begin
        for (k, v) in d
            if k in nounit
                d[k] = ustrip(v)
            end
        end
    end
    process!(args)
    process!(kwargs)
    call(e, values(args), kwargs)
end

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

getvar!(x::Var) = x
getvar!(x) = missing
getvar!(s::System, n::Symbol) = getvar(s, n)
getvar!(s::System, l::Vector) = begin
    #HACK: manual reduction due to memory allocations
    #reduce((a, b) -> getvar!(a, b), [s; l])
    a = s
    for b in l
        a = getvar!(a, b)
    end
    a
end
getvar!(s::System, n::AbstractString) = getvar!(varpath(s, n))

getvar!(x::Var{Produce}, o::VarOpAll) = value!(x)
getvar!(x::Var{Produce}, o::VarOpRecursiveAll) = begin
    v = value!(x)
    l = System[]
    #TODO: possibly reduce overhead by reusing calculated values in child nodes
    f(v) = (append!(l, v); foreach(s -> f.(value!(s, x.name)), v); l)
    f(v)
end
getvar!(v::Vector{<:System}, o::VarOpIndex) = begin
    n = length(v)
    i = o.index
    i = (i >= 0) ? i : n+i+1
    (1 <= i <= n) ? [v[i]] : System[]
end
getvar!(v::Vector{<:System}, o::VarOpFilter) = filter(s -> value!(s, Symbol(o.cond)), v)
getvar!(s::Vector, n::Symbol) = getvar.(s, n)

check!(x::Var) = check!(state(x))
update!(x::Var) = update!(x, MainStep())
update!(x::Var, t::Step) = (s = state(x); queue!(system(x).context, store!(s, x, t), flushorder(s)))

value(x::Var) = value(state(x))
value(x) = x
value(s::System, n) = s[n]

value!(x::Var) = value!(x, MainStep())
value!(x::Var, t::Step) = (check!(x) && update!(x, t); value(x))
value!(x) = x
value!(x::Vector{<:Var}) = value!.(x)
value!(s::System, n) = value!(getvar!(s, n))

priority(::Type{Var{S}}) where {S<:State} = priority(S)
flushorder(::Type{Var{S}}) where {S<:State} = flushorder(S)

advance!(x::Var{Advance}) = advance!(state(x))
reset!(x::Var{Advance}) = reset!(state(x))

import Base: convert, promote_rule
convert(::Type{System}, x::Var) = x.system
convert(::Type{Vector{Symbol}}, x::Var) = [x.name]
convert(::Type{X}, x::Var) where {X<:Var} = x
convert(::Type{V}, x::Var) where {V<:Number} = convert(V, value!(x))
promote_rule(::Type{X}, ::Type{V}) where {X<:Var, V<:Number} = V
promote_rule(::Type{Bool}, ::Type{X}) where {X<:Var} = Bool

import Base: ==, isless
#HACK: would make different Vars with same internal value clash for Dict key
# ==(a::Var, b::Var) = ==(value!(a), value!(b))
==(a::Var, b::V) where {V<:Number} = ==(promote(a, b)...)
==(a::V, b::Var) where {V<:Number} = ==(b, a)
#TODO: reduce redundant declarations of basic functions (i.e. comparison)
isless(a::Var, b::Var) = isless(value!(a), value!(b))
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
