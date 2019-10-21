struct Produce{S<:System} <: State{S}
    name::Symbol # used in recurisve collecting in collect()
    value::Vector{S}
end

struct Product{S<:System}
    type::Type{S}
    args
end
iterate(p::Product) = (p, nothing)
iterate(p::Product, ::Nothing) = nothing

Produce(; _name, _type::Type{S}, _...) where {S<:System} = begin
    Produce{S}(_name, S[])
end

produce(s::Type{<:System}; args...) = Product(s, args)
unit(s::Produce) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
priority(::Type{<:Produce}) = PrePriority()

export produce
