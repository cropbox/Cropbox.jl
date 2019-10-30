abstract type System end

name(s::S) where {S<:System} = string(S)
import Base: names
names(s::S) where {S<:System} = names(S)
names(S::Type{<:System}) = (n = split(String(Symbol(S)), "."); [Symbol(join(n[i:end], ".")) for i in 1:length(n)])

import Base: length, iterate
length(::System) = 1
iterate(s::System) = (s, nothing)
iterate(s::System, i) = nothing

import Base: broadcastable
broadcastable(s::System) = Ref(s)

import Base: getindex
getindex(s::System, i) = getproperty(s, i)

import Base: getproperty
getproperty(s::System, n::String) = begin
    reduce((a, b) -> begin
        m = match(r"([^\[\]]+)(?:\[(.+)\])?", b)
        n, i = m[1], m[2]
        v = getfield(a, Symbol(n))
        !isnothing(i) && (v = getindex(v, parse(Int, i)))
        v
    end, [s, split(n, ".")...])
end

#HACK: swap out state variable of mutable System after initialization
setvar!(s::System, k::Symbol, v) = begin
    setfield!(s, k, v)
    d = Dict(fieldnamesalias(s))
    for a in d[k]
        setfield!(s, a, v)
    end
end

import DataFrames: DataFrame
import ProgressMeter: @showprogress
run!(s::System, n=1; index="context.clock.tick", columns=(), nounit=false) = begin
    C = isempty(columns) ? fieldnamesunique(s) : columns
    N = [index, C...]
    parse(p::Pair) = p
    parse(a::Symbol) = (a => a)
    parse(a::String) = (Symbol(split(a, ".")[end]) => a)
    T = (; parse.(N)...)
    R = []
    K = []
    for (c, k) in pairs(T)
        v = value(s[k])
        if typeof(v) <: Union{Number,Symbol,String}
            push!(R, c => v)
            push!(K, k)
        end
    end
    df = DataFrame(; R...)
    @showprogress for i in 1:n
        update!(s)
        r = Tuple(value(s[k]) for k in K)
        push!(df, r)
    end
    nounit ? deunitfy.(df) : df
end

run!(S::Type{<:System}, n=1; config=configure(), options=(), kwargs...) = begin
    s = instance(S; config=config, options...)
    run!(s, n; kwargs...)
end

import Base: show
show(io::IO, s::System) = print(io, "<$(name(s))>")

export System, run!
