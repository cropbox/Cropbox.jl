struct Production{S<:System}
    type::Type{S}
    args
end
Base.iterate(p::Production) = (p, nothing)
Base.iterate(p::Production, ::Nothing) = nothing
Base.eltype(::Type{Production}) = Production

mutable struct Produce{P,V} <: State{P}
    name::Symbol # used in recurisve collecting in collect()
    value::V
    productions::Vector{Production}
end

Produce(; _name, _type, _...) = begin
    T = _type
    if T <: System
        P = T
        V = Union{System,Nothing}
        v = nothing
    elseif T <: Vector{<:System}
        P = T
        V = Vector{System}
        v = V[]
    end
    Produce{P,V}(_name, v, Production[])
end

produce(s::Type{<:System}; args...) = Production(s, args)
produce(::Nothing; args...) = nothing
unittype(s::Produce) = nothing

Base.getindex(s::Produce{<:System}, i) = i == 1 ? s.value : throw(BoundsError(s, i))
Base.length(s::Produce{<:System}) = isnothing(s.value) ? 0 : 1
Base.iterate(s::Produce{<:System}) = isempty(s) ? nothing : (s.value, nothing)
Base.iterate(s::Produce{<:System}, ::Nothing) = nothing
Base.eltype(::Type{Produce{S}}) where {S<:System} = S

Base.getindex(s::Produce{<:Vector}, i) = getindex(s.value, i)
Base.getindex(s::Produce{<:Vector}, ::Nothing) = s
Base.length(s::Produce{<:Vector}) = length(s.value)
Base.iterate(s::Produce{<:Vector}, i=1) = i > length(s) ? nothing : (s[i], i+1)
Base.eltype(::Type{<:Produce{Vector{S}}}) where {S<:System} = S

Base.isempty(s::Produce) = length(s) == 0

priority(::Type{<:Produce}) = PrePriority()

produce!(s::Produce, ::Nothing) = nothing
produce!(s::Produce, p::Production) = push!(s.productions, p)
produce!(s::Produce, P::Vector) = produce!.(Ref(s), P)

produce!(s::Produce, p::System) = (s.value = p)
produce!(s::Produce{V}, p::System) where {V<:Vector} = push!(s.value, p)

export produce

updatetags!(d, ::Val{:Produce}; _...) = begin
    #HACK: fragile type string check
    d[:single] = !occursin("Vector{", string(d[:_type]))
end

genvartype(v::VarInfo, ::Val{:Produce}; V, _...) = begin
    if istag(v, :single)
        @q Produce{$V,Union{System,Nothing}}
    else
        @q Produce{$V,Vector{System}}
    end
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
            $C.produce!($s, $b)
        end
        empty!($P)
        $C.update!($a, $C.PreStage())
    end
end

# Produce referenced in args expected to be raw state, not extracted by value(), for querying
genupdate(v::VarInfo, ::Val{:Produce}, ::PreStep) = symstate(v)

genupdate(v::VarInfo, ::Val{:Produce}, ::MainStep) = begin
    @gensym s a
    @q let $s = $(symstate(v)),
           $a = $C.value($s)
        $C.update!($a)
        $s
    end
end

genupdate(v::VarInfo, ::Val{:Produce}, ::PostStep) = begin
    @gensym s P
    if istag(v, :single)
        @q let $s = $(symstate(v))
            if isempty($s)
                let $P = $(genfunc(v))
                    $C.produce!($s, $P)
                end
            end
        end
    else
        @q let $s = $(symstate(v)),
               $P = $(genfunc(v))
            $C.produce!($s, $P)
        end
    end
end

genupdate(v::VarInfo, ::Val{:Produce}, ::PostStage) = begin
    @gensym s a
    @q let $s = $(symstate(v)),
           $a = $C.value($s)
        $C.update!($a, $C.PostStage())
    end
end
