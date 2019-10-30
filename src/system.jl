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

parserunkey(p::Pair) = p
parserunkey(a::Symbol) = (a => a)
parserunkey(a::String) = (Symbol(split(a, ".")[end]) => a)
parserun(s::System, index, columns) = begin
    C = isempty(columns) ? fieldnamesunique(s) : columns
    N = [index, C...]
    (; parserunkey.(N)...)
end

import DataFrames: DataFrame
createresult(s::System, ic) = begin
    R = []
    K = []
    for (c, k) in pairs(ic)
        v = value(s[k])
        if typeof(v) <: Union{Number,Symbol,String}
            push!(R, c => v)
            push!(K, k)
        end
    end
    (DataFrame(; R...), K)
end

import ProgressMeter: @showprogress
updateresult!(s::System, n, df, keys; verbose=true) = begin
    t = verbose ? 1 : Inf
    @showprogress t for i in 1:n
        update!(s)
        r = Tuple(value(s[k]) for k in keys)
        push!(df, r)
    end
end

run!(s::System, n=1; index="context.clock.tick", columns=(), verbose=true, nounit=false) = begin
    T = parserun(s, index, columns)
    df, K = createresult(s, T)
    updateresult!(s, n, df, K; verbose=verbose)
    nounit ? deunitfy.(df) : df
end

run!(S::Type{<:System}, n=1; config=(), options=(), kwargs...) = begin
    s = instance(S, config=config, options...)
    run!(s, n; kwargs...)
end

import Base: show
show(io::IO, s::System) = print(io, "<$(name(s))>")

export System, run!
