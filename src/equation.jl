abstract type Equation{V} end

value(e::Equation) = missing

struct StaticEquation{V} <: Equation{V}
    value::V
    name::Symbol
end

value(e::StaticEquation) = e.value

import DataStructures: OrderedDict
mutable struct EquationArg{T<:AbstractDict}
    names::Tuple{Vararg{Symbol}}
    tmpl::T
    overridden::Bool
    tupletype::Type
end

EquationArg{T}(n) where {T<:AbstractDict} = EquationArg{T}(n, T(), false, NamedTuple)
EquationArg{T}(a::EquationArg{T}) where {T<:AbstractDict} = a

struct DynamicEquation{V,F<:Function} <: Equation{V}
    func::F
    name::Symbol
    args::EquationArg
    kwargs::EquationArg
    default::Dict{Symbol,Any}
    body
end

call(e::DynamicEquation, args::Vararg{Any,N}; kwargs...) where N = e.func(args...; kwargs...)

Equation(v, n; kwargs...) = StaticEquation(v, n; kwargs...)
Equation(f, n, a, k, d, b; kwargs...) = Equation{Any}(f, n, a, k, d, b; kwargs...)
Equation{V}(f, n, a, k, d, b; static=false) where V = begin
    if static && length(a) == 0 && length(k) == 0
        StaticEquation(f(), n)
    else
        F = typeof(f)
        eaa = EquationArg{OrderedDict{Symbol,Any}}(a)
        eak = EquationArg{Dict{Symbol,Any}}(k)
        DynamicEquation{V,F}(f, n, eaa, eak, d, b)
    end
end
