abstract type Equation{V} end

value(e::Equation) = missing

struct StaticEquation{V} <: Equation{V}
    value::V
    name::Symbol
end

value(e::StaticEquation) = e.value

struct DynamicEquation{V,F<:Function} <: Equation{V}
    func::F
    name::Symbol
    args::Tuple{Vararg{Symbol}}
    kwargs::Tuple{Vararg{Symbol}}
    default::Dict{Symbol,Any}
end

call(e::DynamicEquation, args::Vararg{Any,N}; kwargs...) where N = e.func(args...; kwargs...)
argsname(e::DynamicEquation) = e.args
kwargsname(e::DynamicEquation) = e.kwargs
default(e::DynamicEquation) = e.default

Equation(v, n; kwargs...) = StaticEquation(v, n; kwargs...)
Equation(f, n, a, k, d; kwargs...) = Equation{Any}(f, n, a, k, d; kwargs...)
Equation{V}(f, n, a, k, d; static=false) where V = begin
    if static && length(a) == 0 && length(k) == 0
        StaticEquation(f(), n)
    else
        F = typeof(f)
        DynamicEquation{V,F}(f, n, a, k, d)
    end
end
