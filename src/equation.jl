abstract type Equation{V} end

value(e::Equation) = missing

struct StaticEquation{V} <: Equation{V}
    value::V
    name::Symbol
end

value(e::StaticEquation) = e.value

import DataStructures: OrderedDict
struct DynamicEquation{V,F<:Function} <: Equation{V}
    func::F
    name::Symbol
    args::OrderedDict{Symbol,Any}
    kwargs::Dict{Symbol,Any}
    default::Dict{Symbol,Any}
end

DynamicEquation(func, name, args::Tuple{Vararg{Symbol}}, kwargs::Tuple{Vararg{Symbol}}, default, V::Type=Any) = begin
    #HACK: create empty dictionaries to be reused
    a = OrderedDict{Symbol,Any}(zip(args, repeat([missing], length(args))))
    k = Dict{Symbol,Any}(zip(kwargs, repeat([missing], length(kwargs))))
    # ensure default values are evaled (i.e. `nothing` instead of `:nothing`)
    d = Dict{Symbol,Any}(k => eval(v) for (k, v) in default)
    F = typeof(func)
    DynamicEquation{V,F}(func, name, a, k, d)
end
DynamicEquation(func, name, args, kwargs, default, V::Type=Any) = begin
    F = typeof(func)
    DynamicEquation{V,F}(func, name, args, kwargs, default)
end

call(e::DynamicEquation, args, kwargs) = e.func(args...; kwargs...)
getargs(e::DynamicEquation) = e.args
getkwargs(e::DynamicEquation) = e.kwargs
default(e::DynamicEquation) = e.default

Equation(value, name) = StaticEquation(value, name)
Equation(func, name, args, kwargs, default, V::Type=Any) = begin
    if length(args) == 0 && length(kwargs) == 0
        StaticEquation(func(), name)
    else
        DynamicEquation(func, name, args, kwargs, default, V)
    end
end
