mutable struct Var{S<:State,N}
    system::System
    state::S
    equation::Equation
    name::Symbol
    alias::Vector{Symbol}
    nounit::Vector{Symbol}

    Var(s, e, ::Type{S}; _name, _alias=Symbol[], _value, nounit="", stargs...) where {S<:State} = begin
        N = Symbol("$(name(s))<$_name>")
        x = new{S,N}(s)
        init_names!(x, _name, _alias)
        init_nounit!(x, nounit)
        init_equation!(x, e)
        init_state!(x, S, _name, _value, stargs...)
        x
    end
end

init_names!(x::Var, name, alias) = (x.name = name; x.alias = alias)
init_nounit!(x::Var, s::String) = (x.nounit = Symbol.(split(s, ","; keepempty=false)))
init_equation!(x::Var, e::Equation) = begin
    s = x.system
    c = s.context.config
    # patch default arguments from config
    patch!(a::Symbol) = begin
        # 1. external options (i.e. TOML config)
        v = option(c, s, x, a)
        !isnothing(v) && (default(e)[a] = v)
    end
    patch!.(getargs(e))
    # patch state variable from config
    v = option(c, s, x)
    #HACK: avoid Dict used for partial argument patch
    if !isnothing(v) && !(typeof(v) <: Dict)
        x.equation = Equation(v, e.name)
    else
        x.equation = e
    end
end
init_state!(x::Var, ::Type{S}, n::Symbol, v, stargs...) where {S<:State} = begin
    v = ismissing(v) ? value(x.equation) : v
    x.state = S(; _name=n, _system=x.system, _var=x, _value=v, stargs...)
end

name(x::Var) = x.name
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
        v = get(default(x.equation), a, nothing)
        !isnothing(v) && return interpret(v)

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
    vargs = Vector([pargs...])
    margs = [(ismissing(v) && (v = popfirst!(vargs)); a => v) for (a, v) in args]
    @assert isempty(vargs) "too many positional arguments: $vargs"
    mkwargs = merge(Dict.([kwargs, pkwargs])...) |> collect
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

check!(x::Var) = check!(x.state)
update!(x::Var) = queue!(x.system.context, store!(x.state, () -> x()), priority(x.state))

value(x::Var) = value(x.state)
value(x) = x
value(s::System, n) = s[n]

value!(x::Var) = (check!(x) && update!(x); value(x))
value!(x) = x
value!(x::Vector{<:Var}) = value!.(x)
value!(s::System, n) = value!(getvar!(s, n))

store!(s::State, x::Var) = store!(s, value!(x))

advance!(x::Var{Advance}) = advance!(x.state)
reset!(x::Var{Advance}) = reset!(x.state)

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
getindex(x::Var, i::Integer) = getindex(x.state, i)
length(x::Var) = length(x.state)
iterate(x::Var) = iterate(x.state)
iterate(x::Var, i) = iterate(x.state, i)

import Base: show
show(io::IO, x::Var) = print(io, "$(name(x.system))<$(name(x))> = $(x.state)")

export value
