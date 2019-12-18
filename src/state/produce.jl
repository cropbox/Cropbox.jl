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
eltype(::Product) = Product

Produce(; _name, _type::Type{S}, _...) where {S<:System} = begin
    Produce{S}(_name, S[])
end

produce(s::Type{<:System}; args...) = Product(s, args)
unit(s::Produce) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
getindex(s::Produce, ::Nothing) = s
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
eltype(::Produce{S}) where {S<:System} = S
priority(::Type{<:Produce}) = PrePriority()

export produce

genvartype(v::VarInfo, ::Val{:Produce}; _...) = begin
    S = isnothing(v.type) ? :System : esc(v.type)
    @q Produce{$S}
end

geninit(v::VarInfo, ::Val{:Produce}) = nothing

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
    @gensym s P c q a p b
    @q let $s = $(symstate(v)),
           $P = $(genfunc(v)),
           $c = context,
           $q = context.queue,
           $a = $C.value($s)
        if !(isnothing($P) || isempty($P))
            $C.queue!($q, function ()
                for $p in $P
                    if $p isa $C.Product
                        $b = $p.type(; context=$c, $p.args...)
                        push!($a, $b)
                    end
                end
            end, $C.priority($C.$(v.state)))
        end
    end
end
