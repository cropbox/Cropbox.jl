struct Bundle{S<:System,P,F}
    produce::Produce{P}
    recursive::Bool
    filter::F
end

Bundle(p::Produce{P,V}, ops::AbstractString) where {P,V} = begin
    recursive = false
    filter = nothing
    index = 0
    for op in split(ops, "/")
        if op == "*"
            # collecting children only at the current level
            recursive = false
        elseif op == "**"
            # collecting all children recursively
            recursive = true
        else
            #TODO: support generic indexing function?
            filter = op
        end
    end
    S = eltype(p)
    F = typeof(filter)
    Bundle{S,P,F}(p, recursive, filter)
end

Base.collect(b::Bundle{S}) where {S<:System} = begin
    p = getfield(b, :produce)
    v = collect(p)
    if getfield(b, :recursive)
        l = S[]
        #TODO: possibly reduce overhead by reusing calculated values in child nodes
        g(V::Vector{<:System}) = for s in V; g(s) end
        g(s::System) = (push!(l, s); g(value(getfield(s, p.name))))
        g(::Nothing) = nothing
        g(v)
    else
        l = copy(v)
    end
    f = getfield(b, :filter)
    if !isnothing(f)
        filter!(s -> value(s[f]), l)
    end
    l
end

Base.getindex(s::Produce, ops::AbstractString) = Bundle(s, ops)

struct Bunch{V}
    it::Base.Generator
end

Base.iterate(b::Bunch, i...) = iterate(getfield(b, :it), i...)
Base.length(b::Bunch) = length(getfield(b, :it))
Base.eltype(::Type{<:Bunch{<:State{V}}}) where V = V

Base.getproperty(b::Bundle{S}, p::Symbol) where {S<:System} = (value(getfield(x, p)) for x in value(b)) |> Bunch{vartype(S, p)}
Base.getproperty(b::Bunch{S}, p::Symbol) where {S<:System} = (value(getfield(x, p)) for x in b) |> Bunch{vartype(S, p)}
Base.getindex(b::Bundle, i::AbstractString) = getproperty(b, Symbol(i))
Base.getindex(b::Bunch, i::AbstractString) = getproperty(b, Symbol(i))

value(b::Bundle) = collect(b)
#TODO: also make final value() based on generator, but then need sum(x; init=0) in Julia 1.6 for empty generator
#value(b::Bunch) = (value(v) for v in b)
value(b::Bunch) = collect(b)

Base.getindex(b::Bundle) = value(b)
Base.getindex(b::Bunch) = value(b)

Base.adjoint(b::Bundle) = value(b)
Base.adjoint(b::Bunch) = value(b)
