abstract type BundleOperator end

struct BundleAll <: BundleOperator end
struct BundleRecursiveAll <: BundleOperator end
struct BundleIndex{I<:Number} <: BundleOperator
    index::I
end
struct BundleFilter{S<:AbstractString} <: BundleOperator
    cond::S
end

struct Bundle{S<:System,P}
    root::Produce{P}
    ops::Vector{BundleOperator}
end

resolveindex(op::AbstractString) = begin
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

Base.getindex(s::Produce{Union{S,Nothing}}, ops::AbstractString) where {S<:System} = Bundle{S,Union{S,Nothing}}(s, resolveindex.(split(ops, "/")))
Base.getindex(s::Produce{Vector{S}}, ops::AbstractString) where {S<:System} = Bundle{S,Vector{S}}(s, resolveindex.(split(ops, "/")))

fieldnamesunique(::Bundle{S}) where {S<:System} = fieldnamesunique(S)
fieldnamesalias(::Bundle{S}) where {S<:System} = fieldnamesalias(S)

struct Bunch{V}
    list::Vector{V}
end

Base.getproperty(b::Bundle{S}, p::Symbol) where {S<:System} = getfield.(collect(b), p) |> Bunch{fieldtype(S, p)}
Base.getproperty(b::Bunch{S}, p::Symbol) where {S<:System} = getfield.(collect(b), p) |> Bunch{fieldtype(S, p)}
Base.getindex(b::Bundle, i::AbstractString) = getproperty(b, Symbol(i))
Base.getindex(b::Bunch, i::AbstractString) = getproperty(b, Symbol(i))
value(b::Bunch) = value.(collect(b))

Base.collect(b::Bundle) = reduce((a, b) -> collect(a, b), Any[getfield(b, :root), getfield(b, :ops)...])
Base.collect(b::Bunch) = getfield(b, :list)
Base.collect(p::Produce, ::BundleAll) = value(p)
Base.collect(p::Produce, ::BundleRecursiveAll) = begin
    l = System[]
    #TODO: possibly reduce overhead by reusing calculated values in child nodes
    f(s::System) = (push!(l, s); f.(value(getfield(s, p.name))))
    f(::Nothing) = nothing
    f.(value(p))
    l
end
Base.collect(V::Vector{S}, o::BundleIndex) where {S<:System} = begin
    n = length(V)
    i = o.index
    i = (i >= 0) ? i : n+i+1
    (1 <= i <= n) ? [V[i]] : S[]
end
Base.collect(V::Vector{<:System}, o::BundleFilter) = filter(s -> value(getfield(s, Symbol(o.cond))), V)

Base.adjoint(b::Bundle) = collect(b)
Base.adjoint(b::Bunch) = [v' for v in collect(b)]
