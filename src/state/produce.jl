struct Production{S<:System}
    type::Type{S}
    args
end
iterate(p::Production) = (p, nothing)
iterate(p::Production, ::Nothing) = nothing
eltype(::Type{Production}) = Production

struct Produce{S<:System} <: State{S}
    name::Symbol # used in recurisve collecting in collect()
    value::Vector{System}
    productions::Vector{Production}
end

Produce(; _name, _type::Type{S}, _...) where {S<:System} = begin
    Produce{S}(_name, S[], Production[])
end

produce(s::Type{<:System}; args...) = Production(s, args)
produce(::Nothing; args...) = nothing
unit(s::Produce) = nothing
getindex(s::Produce, i) = getindex(s.value, i)
getindex(s::Produce, ::Nothing) = s
length(s::Produce) = length(s.value)
iterate(s::Produce, i=1) = i > length(s) ? nothing : (s[i], i+1)
eltype(::Type{Produce{S}}) where {S<:System} = S
priority(::Type{<:Produce}) = PrePriority()
setproduction!(s::Produce, ::Nothing) = nothing
setproduction!(s::Produce, p::Production) = push!(s.productions, p)
setproduction!(s::Produce, P::Vector) = setproduction!.(Ref(s), P)

export produce

genvartype(v::VarInfo, ::Val{:Produce}; N, _...) = begin
    @q Produce{$N}
end

geninit(v::VarInfo, ::Val{:Produce}) = nothing

genupdate(v::VarInfo, ::Val{:Produce}, ::PreStage) = begin
    @gensym s a P c p b
    @q let $s = $(symstate(v)),
           $a = $C.value($s),
           $P = $s.productions,
           $c = context
        for $p in $P
            $b = $p.type(; context=$c, $p.args...)
            push!($a, $b)
        end
        empty!($P)
        $C.update!($a, $C.PreStage())
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
        $C.setproduction!($s, $P)
    end
end

genupdate(v::VarInfo, ::Val{:Produce}, ::PostStage) = begin
    @gensym s a
    @q let $s = $(symstate(v)),
           $a = $C.value($s)
        $C.update!($a, $C.PostStage())
    end
end
