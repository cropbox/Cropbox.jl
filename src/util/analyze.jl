import GlobalSensitivity
using StatsBase: StatsBase, mean
using DataFrames

"""
    analyze(S; <keyword arguments>) -> DataFrame | Any

Perform a global sensitivity analysis on a system `S` using the specified method from GlobalSensitivity.jl.
This function quantifies how variations in model parameters affect the output variable of interest.

# Arguments
- `S::Type{<:System}`: type of system to be analyzed.

# Keyword Arguments
## Configuration
- `config=()`: a single base configuration for the system (can't be used with `configs`).
- `configs=[]`: multiple base configurations for the system (can't be used with `config`).

## Parameters
- `target`: a variable specifying the output variable to analyze.
- `parameters`: parameter specification with a range of boundary values.
- `method`: sensitivity analysis method, e.g., `:Morris`, `:Sobol`, or an instance of `GSAMethod`.
- `samples`: number of samples to use for the analysis.

## Additional
- Remaining keyword arguments are passed down to `simulate` with regard to running system `S`.

# Returns
- A DataFrame or object containing the result of the analysis.

See also: [`simulate`](@ref), [`@config`](@ref)

# Examples
```julia-repl
julia> @system S(Controller) begin
           a => 0 ~ preserve(parameter)
           b(a) => a^2 ~ track
       end;

julia> a = analyze(S, target=:b, parameters=:S => :a => (-10, 10), method=:Morris, samples=1000)
...
```
"""
analyze(S::Type{<:System}; config=(), configs=[], kwargs...) = begin
    if isempty(configs)
        analyze(S, [config]; kwargs...)
    elseif isempty(config)
        analyze(S, configs; kwargs...)
    else
        @error "redundant configurations" config configs
    end
end
analyze(S::Type{<:System}, configs::Vector; target, parameters, method, option=(), samples, kwargs...) = begin
    if isempty(configs)
        configs = [@config]
    end

    P = configure(parameters)
    K = parameterkeys(P)
    V = parametervalues(P)
    U = parameterunits(P)
    r = map((p, u) -> Float64.(Tuple(deunitfy(p, u))), V, U)

    T = parsetarget(target, S) |> keys |> collect
    length(T) > 1 && @error "multiple targets specified" target

    f(X) = begin
        c1 = parameterzip(K, X, U)
        l = length(configs)
        R = Vector(undef, l)
        Threads.@threads for i in 1:l
            c = @config(configs[i], c1)
            r = simulate(S; config=c, target, kwargs..., verbose=false)
            R[i] = r[end, target]
        end
        R |> mean |> deunitfy
    end

    m = if method == :Morris
        GlobalSensitivity.Morris(; option...)
    elseif method == :Sobol
        GlobalSensitivity.Sobol(; option...)
    elseif method isa GlobalSensitivity.GSAMethod
        method
    else
        @error "unknown method" method
    end

    a = GlobalSensitivity.gsa(f, m, r; samples)
    KS = first.(K)
    KP = last.(K)
    if a isa GlobalSensitivity.MorrisResult
        DataFrame(system = KS, parameter = KP, means = a.means[1,:], means_star = a.means_star[1,:], variances = a.variances[1,:])
    elseif a isa GlobalSensitivity.SobolResult
        DataFrame(system = KS, parameter = KP, ST = a.ST, S1 = a.S1)
    else
        a
    end
end

export analyze
