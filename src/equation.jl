abstract type Equation end

value(e::Equation) = missing
getargs(e::Equation) = Symbol[]
getkwargs(e::Equation) = Symbol[]
default(e::Equation) = Dict{Symbol,Any}()

struct StaticEquation{V} <: Equation
    value::V
    name::Symbol
end

call(e::StaticEquation, args, kwargs) = value(e)
value(e::StaticEquation) = e.value

struct DynamicEquation{F<:Function} <: Equation
    func::F
    name::Symbol
    args::Vector{Symbol}
    kwargs::Vector{Symbol}
    default::Dict{Symbol,Any}
end

call(e::DynamicEquation, args, kwargs) = e.func(args...; kwargs...)
getargs(e::DynamicEquation) = e.args
getkwargs(e::DynamicEquation) = e.kwargs
default(e::DynamicEquation) = e.default

Equation(value, name) = StaticEquation(value, name)
Equation(func, name, args, kwargs, default) = begin
    if length(args) == 0 && length(kwargs) == 0
        StaticEquation(func(), name)
    else
        # ensure default values are evaled (i.e. `nothing` instead of `:nothing`)
        d = Dict{Symbol,Any}(k => eval(v) for (k, v) in default)
        DynamicEquation(func, name, args, kwargs, d)
    end
end
