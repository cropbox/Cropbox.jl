mutable struct Var{S<:State,V,N}
    system::System
    state::State{V}
    equation::Equation
    name::Symbol
    alias::Vector{Symbol}
    nounit::Vector{Symbol}

    Var(s, e, ::Type{S}; _name, _alias=Symbol[], _value, nounit="", stargs...) where {S<:State} = begin
        e = patch(s, e, [_name; _alias])
        v = ismissing(_value) ? value(e) : _value
        st = S(; _name=_name, _system=s, _value=v, stargs...)
        nu = Symbol.(split(nounit, ","; keepempty=false))
        V = valuetype(st)
        N = Symbol("$(name(s))<$_name>")
        x = new{S,V,N}(s, st, e, _name, _alias, nu)
    end
end

patch(s::System, e::Equation, n) = begin
    c = s.context.config
    # patch default arguments from config
    patch!(a::Symbol) = begin
        # 1. external options (i.e. TOML config)
        v = option(c, s, n, a)
        !isnothing(v) && (default(e)[a] = v)
    end
    patch!.(getargs(e))
    # patch state variable from config
    v = option(c, s, n)
    #HACK: avoid Dict used for partial argument patch
    if !isnothing(v) && !(typeof(v) <: Dict)
        Equation(v, e.name)
    else
        e
    end
end

name(x::Var) = x.name
import Base: names
names(x::Var) = [[x.name]; x.alias]

state(x::Var{S,V}) where {S<:State,V} = x.state::S{V}

(x::Var)() = begin
    s = x.system
    #TODO: use var path exclusive str (i.e. v_str)
    #TODO: unit handling (i.e. u_str)
    interpret(v::Symbol) = value!(s, v)
    interpret(v::String) = value!(s, v)
    interpret(v) = v
    resolve(a::Symbol) = begin
        # 2. default parameter values
        v = get(default(x.equation), a, missing)
        !ismissing(v) && return interpret(v)

        # 3. state vars from current system
        isdefined(s, a) && return interpret(a)

        # 4. argument not found (partial function used by Call State)
        missing
    end
    pair(a::Symbol) = a => resolve(a)
    args = pair.(getargs(x.equation))
    kwargs = filter(!ismissing, pair.(getkwargs(x.equation)))
    handle(x, args, kwargs)
end
handle(x::Var, args, kwargs) = call(x, args, kwargs)
handle(x::Var{Call}, args, kwargs) = function (pargs...; pkwargs...)
    # arg
    i = 1
    margs = [(ismissing(v) && (v = pargs[i]; i += 1); a => v) for (a, v) in args]
    @assert i-1 == length(pargs) "too many positional arguments: $vargs"
    # kwarg
    dkwargs = Dict{Symbol,Any}(kwargs)
    merge!(dkwargs, pkwargs)
    mkwargs = dkwargs |> collect
    call(x, margs, mkwargs)
end
call(x::Var, args, kwargs) = begin
    nounit(a::Symbol) = a in x.nounit ? ustrip : identity
    nounit(p::Pair) = nounit(p[1])(p[2])
    uargs = map(nounit, args)
    ukwargs = map(p -> p[1] => nounit(p), kwargs)
    call(x.equation, uargs, ukwargs)
end

getvar(s::System, n::Symbol) = getfield(s, n)
getvar(s::System, l::Vector{Symbol}) = reduce((a, b) -> getvar(a, b), [s; l])
getvar(s::System, n::String) = getvar(s, Symbol.(split(n, ".")))

getvar!(s::System, n::Symbol) = getvar(s, n)
getvar!(x::Var{Produce}, n::N) where {N<:AbstractString} = begin
    m = match(r"(?<ind>[^/]+)(?:/(?<cond>.+))?", n)
    cond(a) = begin
        c = m[:cond]
        isnothing(c) ? a : filter(s -> value!(s, Symbol(c)), a)
    end
    ind = m[:ind]
    v = value!(x)
    if ind == "*"
        # collecting children only at the current level
        v |> cond
    elseif ind == "**"
        # collecting all children recursively
        l = System[]
        #TODO: possibly reduce overhead by reusing calculated values in child nodes
        f(v) = (append!(l, v); foreach(s -> f.(value!(s, x.name)), v); l)
        f(v) |> cond
    else
        # indexing by number (negative for backwards)
        i = tryparse(Int, ind)
        if !isnothing(i)
            # should be pre-filtered
            v = v |> cond
            n = length(v)
            i = (i >= 0) ? i : n+i+1
            (1 <= i <= n) ? [v[i]] : System[]
        else
            #TODO: support generic indexing function?
        end
    end
end
getvar!(s::Vector, n::Symbol) = getvar.(s, n)
getvar!(x::Vector{Var{Produce}}, n::N) where {N<:AbstractString} = value!.(x, n)
getvar!(s::System, l::Vector) = reduce((a, b) -> getvar!(a, b), [s; l])
getvar!(s::System, n::N) where {N<:AbstractString} = begin
    l = split(n, ".")
    ms = match.(r"(?<key>[^\[\]]+)(?:\[(?<op>.+)\])?", l)
    f(m) = begin
        key = Symbol(m[:key])
        op = m[:op]
        isnothing(op) ? [key] : [key, op]
    end
    getvar!(s, f.(ms) |> Iterators.flatten |> collect)
end

check!(x::Var) = check!(state(x))
update!(x::Var) = (s = state(x); queue!(x.system.context, store!(s, () -> x()), priority(s)))

value(x::Var) = value(state(x))
value(x) = x
value(s::System, n) = s[n]

value!(x::Var) = (check!(x) && update!(x); value(x))
value!(x) = x
value!(x::Vector{<:Var}) = value!.(x)
value!(s::System, n) = value!(getvar!(s, n))

store!(s::State, x::Var) = store!(s, value!(x))

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
==(a::Var, b::Var) = ==(value!(a), value!(b))
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
