struct Equation
    func::Function #TODO: parametrise {F<:Function}
    name::Symbol
    args::Vector{Symbol}
    kwargs::Vector{Symbol}
    default::Dict{Symbol,Any}
end

(e::Equation)(args...; kwargs...) = e.func(args...; kwargs...)
