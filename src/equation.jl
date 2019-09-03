abstract type Equation{V} end

value(e::Equation) = missing

struct StaticEquation{V} <: Equation{V}
    value::V
    name::Symbol
end

value(e::StaticEquation) = e.value

import DataStructures: OrderedDict
mutable struct EquationArg
    names::Tuple{Vararg{Symbol}}
    tmpl::OrderedDict{Symbol,Any}
    work::OrderedDict{Symbol,Any}
    overridden::Bool
end

EquationArg(n) = EquationArg(n, OrderedDict{Symbol,Any}(), OrderedDict{Symbol,Any}(), false)
EquationArg(a::EquationArg) = a

struct DynamicEquation{V,F<:Function} <: Equation{V}
    func::F
    name::Symbol
    args::EquationArg
    kwargs::EquationArg
    default::Dict{Symbol,Any}
end

call(e::DynamicEquation, args::Vararg{Any,N}; kwargs...) where N = e.func(args...; kwargs...)

Equation(v, n; kwargs...) = StaticEquation(v, n; kwargs...)
Equation(f, n, a, k, d; kwargs...) = Equation{Any}(f, n, a, k, d; kwargs...)
Equation{V}(f, n, a, k, d; static=false) where V = begin
    if static && length(a) == 0 && length(k) == 0
        StaticEquation(f(), n)
    else
        F = typeof(f)
        DynamicEquation{V,F}(f, n, EquationArg(a), EquationArg(k), d)
    end
end
