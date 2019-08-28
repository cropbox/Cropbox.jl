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

DynamicEquation(func, name, args, kwargs, default, V::Type=Any) = begin
    F = typeof(func)
    DynamicEquation{V,F}(func, name, args, kwargs, default)
end

call(e::DynamicEquation, args, kwargs) = e.func(args...; kwargs...)
argsname(e::DynamicEquation) = e.args
kwargsname(e::DynamicEquation) = e.kwargs
default(e::DynamicEquation) = e.default

Equation(value, name) = StaticEquation(value, name)
Equation(func, name, args, kwargs, default, V::Type=Any) = begin
    if length(args) == 0 && length(kwargs) == 0
        StaticEquation(func(), name)
    else
        DynamicEquation(func, name, args, kwargs, default, V)
    end
end
