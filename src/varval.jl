abstract type VarOp end

struct VarPath
    system::System
    path::Vector{Union{Symbol,VarOp}}
end

struct VarOpAll <: VarOp end
struct VarOpRecursiveAll <: VarOp end
struct VarOpIndex{I<:Number} <: VarOp
    index::I
end
struct VarOpFilter{S<:AbstractString} <: VarOp
    cond::S
end
resolveop(op::AbstractString) = begin
    if op == "*"
        # collecting children only at the current level
        VarOpAll()
    elseif op == "**"
        # collecting all children recursively
        VarOpRecursiveAll()
    else
        i = tryparse(Int, op)
        if !isnothing(i)
            VarOpIndex(i)
        else
            #TODO: support generic indexing function?
            VarOpFilter(op)
        end
    end
end
resolveops(ops::AbstractString) = resolveop.(split(ops, "/"))
resolveops(::Nothing) = ()
resolvepath(p::Vector{<:AbstractString}) = begin
    ms = match.(r"(?<key>[^\[\]]+)(?:\[(?<ops>.+)\])?", p)
    resolve(m) = begin
        key = Symbol(m[:key])
        ops = resolveops(m[:ops])
        (key, ops...)
    end
    resolve.(ms) |> Iterators.flatten |> collect
end

varpath(s::System, p::Vector{<:AbstractString}) = VarPath(s, resolvepath(p))
varpath(s::System, p::Symbol) = vartpath(s, [p])
varpath(s::System, n::AbstractString) = varpath(s, split(n, "."))

getvar(p::VarPath) = getvar(p.system, p.path)
getvar!(p::VarPath) = getvar!(p.system, p.path)
value(p::VarPath) = value(getvar(p))
value!(p::VarPath) = value!(getvar!(p))

import Base: convert
convert(::Type{V}, p::VarPath) where {V<:Number} = convert(V, value!(p))
convert(::Type{V}, p::VarPath) where {V<:Quantity} = convert(V, unitfy(value!(p), unit(V)))

struct VarVal{V}
    v::Union{VarPath,V}
end

VarVal{V}(s::System, p::AbstractString) where V = VarVal{V}(varpath(s, p))
VarVal{V}(s::System, p::Number) where {V<:Number} = VarVal{V}(convert(V, p))
VarVal{V}(s::System, p::Number) where {V<:Quantity} = VarVal{V}(convert(V, unitfy(p, unit(V))))
VarVal{V}(s::System, ::Nothing) where V = nothing
VarVal(s::System, p::AbstractString) = VarVal{Any}(s, p)
VarVal(s::System, p::V) where V = VarVal{V}(s, p)

value(v::VarVal) = value(v.v)
value!(v::VarVal) = value!(v.v)
