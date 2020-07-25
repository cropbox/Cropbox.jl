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

Base.getindex(s::Produce{S}, ops::AbstractString) where {S<:System} = Bundle{typefor(S),S}(s, resolveindex.(split(ops, "/")))
Base.getindex(s::Produce{Vector{S}}, ops::AbstractString) where {S<:System} = Bundle{typefor(S),Vector{S}}(s, resolveindex.(split(ops, "/")))

fieldnamesunique(::Bundle{S}) where {S<:System} = fieldnamesunique(S)
fieldnamesalias(::Bundle{S}) where {S<:System} = fieldnamesalias(S)

struct Bunch{V}
    it::Base.Generator
end

Base.iterate(b::Bunch, i...) = iterate(getfield(b, :it), i...)
Base.length(b::Bunch) = length(getfield(b, :it))
Base.eltype(::Type{<:Bunch{<:State{V}}}) where V = V

Base.getproperty(b::Bundle{S}, p::Symbol) where {S<:System} = (getfield(x, p) for x in collect(b)) |> Bunch{vartype(S, p)}
Base.getproperty(b::Bunch{S}, p::Symbol) where {S<:System} = (getfield(x, p) for x in getfield(b, :it)) |> Bunch{vartype(S, p)}
Base.getindex(b::Bundle, i::AbstractString) = getproperty(b, Symbol(i))
Base.getindex(b::Bunch, i::AbstractString) = getproperty(b, Symbol(i))
#TODO: also make final value() based on generator, but then need sum(x; init=0) in Julia 1.6 for empty generator
#value(b::Bunch{<:State{V}}) where V = (value(v) for v in getfield(b, :it))
value(b::Bunch{<:State{V}}) where V = V[value(v) for v in getfield(b, :it)]

Base.collect(b::Bundle) = reduce((a, b) -> collect(a, b), Any[getfield(b, :root), getfield(b, :ops)...])
Base.collect(p::Produce, ::BundleAll) = value(p)
Base.collect(p::Union{Produce{S},Produce{Vector{S}}}, ::BundleRecursiveAll) where {S<:System} = begin
    l = S[]
    #TODO: possibly reduce overhead by reusing calculated values in child nodes
    f(V::Vector{<:System}) = for s in V; f(s) end
    f(s::System) = (push!(l, s); f(value(getfield(s, p.name))))
    f(::Nothing) = nothing
    f(value(p))
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
Base.adjoint(b::Bunch) = value(b)
