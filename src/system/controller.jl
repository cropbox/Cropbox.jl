import Random

@system Controller begin
    config ~ ::Config(override)
    context(config) ~ ::Context(context)
end

"""
    instance(S; <keyword arguments>) -> S

Make an instance of system `S` with an initial condition specified in configuration and additional options.

See also: [`@config`](@ref), [`simulate`](@ref)

# Arguments
- `S::Type{<:System}`: type of system to be instantiated.

# Keyword Arguments
- `config=()`: configuration containing parameter values for the system.
- `options=()`: keyword arguments passed down to the constructor of `S`; named tuple expected.
- `seed=nothing`: random seed initialized before parsing configuration and making an instance.

# Examples
```julia-repl
julia> @system S(Controller) begin
           a => 1 ~ preserve(parameter)
           b(a) ~ accumulate
       end;

julia> instance(S)
S
  context = <Context>
  config = <Config>
  a = 1.0
  b = 0.0
```
"""
instance(S::Type{<:System}; config=(), options=(), seed=nothing) = begin
    !isnothing(seed) && Random.seed!(seed)
    c = configure(config)
    #HACK: support placeholder (0) for the controller name
    c = configure(((k == Symbol(0) ? namefor(S) : k) => v for (k, v) in c)...)
    s = S(; config=c, options...)
    update!(s)
end

export Controller, instance
