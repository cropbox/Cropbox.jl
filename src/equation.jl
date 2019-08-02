struct Equation
    func::Function #TODO: parametrise {F<:Function}
    args::Vector{Symbol}
    kwargs::Vector{Symbol}
    default::Dict{Symbol,Any}

    function Equation(f::Function)
        # https://discourse.julialang.org/t/extract-argument-names/862
        # https://discourse.julialang.org/t/retrieve-default-values-of-keyword-arguments/19320
        ml = methods(f)
        m = ml.ms[end]
        # args = first.(Base.arg_decl_parts(m)[2][2:end])
        args = Base.method_argnames(m)[2:end]
        # https://discourse.julialang.org/t/is-there-a-way-to-get-keyword-argument-names-of-a-method/20454
        #kwargs = Base.kwarg_decl(m, typeof(ml.mt.kwsorter))
        kwargs = Vector{Symbol}()
        default = Dict{Symbol,Any}()
        new(f, args, kwargs, default)
    end
end

(e::Equation)(args...; kwargs...) = e.func(args...; kwargs...)

import Base: convert
convert(T::Type{Equation}, f::Function) = Equation(f)

export Equation
