struct Product{S<:System}
    type::Type{S}
    args
end
iterate(p::Product) = (p, nothing)
iterate(p::Product, ::Nothing) = nothing
eltype(::Type{Product}) = Product

struct Produce{S<:System} <: State{S}
    name::Symbol # used in recurisve collecting in collect()
    value::Vector{System}
    products::Vector{Product}
end

Produce(; _name, _type::Type{S}, _...) where {S<:System} = begin
    Produce{S}(_name, S[], Product[])
end

produce(s::Type{<:System}; args...) = Product(s, args)
produce(::Nothing; args...) = nothing
unit(s::Produce) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
getindex(s::Produce, ::Nothing) = s
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
eltype(::Type{Produce{S}}) where {S<:System} = S
priority(::Type{<:Produce}) = PrePriority()
setproduct!(s::Produce, ::Nothing) = nothing
setproduct!(s::Produce, p::Product) = push!(s.products, p)
setproduct!(s::Produce, P::Vector) = setproduct!.(Ref(s), P)

export produce

genvartype(v::VarInfo, ::Val{:Produce}; N, _...) = begin
    @q Produce{$N}
end

geninit(v::VarInfo, ::Val{:Produce}) = nothing

genpreupdate(v::VarInfo, ::Val{:Produce}) = begin
    @gensym s a P c p b
    @q let $s = $(symstate(v)),
           $a = $C.value($s),
           $P = $s.products,
           $c = context
        for $p in $P
            $b = $p.type(; context=$c, $p.args...)
            push!($a, $b)
        end
        empty!($P)
        $C.update!($a, $C.PreStep())
    end
end

# Produce referenced in args expected to be raw state, not extracted by value(), for querying
genupdate(v::VarInfo, ::Val{:Produce}, ::PreStep) = symstate(v)

genupdate(v::VarInfo, ::Val{:Produce}, ::MainStep) = begin
    @gensym s b
    @q let $s = $(symstate(v))
        for $b in $C.value($s)
            $C.update!($b)
        end
        $s
    end
end

genupdate(v::VarInfo, ::Val{:Produce}, ::PostStep) = begin
    @gensym s P
    @q let $s = $(symstate(v)),
           $P = $(genfunc(v))
        $C.setproduct!($s, $P)
    end
end

genpostupdate(v::VarInfo, ::Val{:Produce}) = begin
    @gensym s a
    @q let $s = $(symstate(v)),
           $a = $C.value($s)
        $C.update!($a, $C.PostStep())
    end
end
