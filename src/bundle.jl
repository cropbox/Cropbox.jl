abstract type BundleOperator end

struct BundleAll <: BundleOperator end
struct BundleRecursiveAll <: BundleOperator end
struct BundleIndex{I<:Number} <: BundleOperator
    index::I
end
struct BundleFilter{S<:AbstractString} <: BundleOperator
    cond::S
end

struct Bundle{S<:System}
    root::Produce{S}
    ops::Vector{BundleOperator}
end

import Base: getindex
getindex(s::Produce{S}, ops::AbstractString) where {S<:System} = begin
    resolve(op::AbstractString) = begin
        if op == "*"
            # collecting children only at the current level
            BundleAll()
        elseif op == "**"
            # collecting all children recursively
            BundleRecursiveAll()
        else
            i = tryparse(Int, op)
            if !isnothing(i)
                BundleIndex(i)
            else
                #TODO: support generic indexing function?
                BundleFilter(op)
            end
        end
    end
    Bundle{S}(s, resolve.(split(ops, "/")))
end

fieldnamesunique(::Bundle{S}) where {S<:System} = fieldnamesunique(S)
fieldnamesalias(::Bundle{S}) where {S<:System} = fieldnamesalias(S)

struct Bunch{V}
    list::Vector{V}
end

import Base: getproperty
getproperty(b::Bundle{S}, p::Symbol) where {S<:System} = getfield.(collect(b), p) |> Bunch{fieldtype(S, p)}
getproperty(b::Bunch{S}, p::Symbol) where {S<:System} = getfield.(collect(b), p) |> Bunch{fieldtype(S, p)}
getindex(b::Bundle, i::AbstractString) = getproperty(b, Symbol(i))
getindex(b::Bunch, i::AbstractString) = getproperty(b, Symbol(i))
value(b::Bunch) = value.(collect(b))

import Base: collect
collect(b::Bundle{S}) where S = reduce((a, b) -> collect(a, b), Any[getfield(b, :root), getfield(b, :ops)...])::Vector{<:S}
collect(b::Bunch) = getfield(b, :list)
collect(p::Produce, ::BundleAll) = value(p)
collect(p::Produce{S}, ::BundleRecursiveAll) where S = begin
    V = value(p)
    l = S[]
    #TODO: possibly reduce overhead by reusing calculated values in child nodes
    f(V) = (append!(l, V); foreach(s -> f.(value(getfield(s, p.name))), V); l)
    f(V)
end
collect(V::Vector{S}, o::BundleIndex) where {S<:System} = begin
    n = length(V)
    i = o.index
    i = (i >= 0) ? i : n+i+1
    (1 <= i <= n) ? [V[i]] : S[]
end
collect(V::Vector{<:System}, o::BundleFilter) = filter(s -> value(getfield(s, Symbol(o.cond))), V)
