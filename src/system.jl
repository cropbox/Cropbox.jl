abstract type System end

namefor(s::S) where {S<:System} = namefor(S)
namefor(S::Type{<:System}) = nameof(S)
Base.names(s::S) where {S<:System} = names(S)
Base.names(S::Type{<:System}) = (n = split(String(Symbol(S)), "."); [Symbol(join(n[i:end], ".")) for i in 1:length(n)])

Base.length(s::System) = length(fieldnamesunique(s))
Base.iterate(s::System) = iterate(s, 1)
Base.iterate(s::System, i) = begin
    F = fieldnamesunique(s)
    l = length(F)
    l == 0 ? nothing : (s[F[i]], l == i ? nothing : i+1)
end
Base.iterate(s::System, ::Nothing) = nothing

Base.broadcastable(s::System) = Ref(s)

Base.getindex(s::System, i) = getproperty(s, i)
Base.getindex(s::System, ::Nothing) = s

Base.getproperty(s::System, n::String) = begin
    reduce((a, b) -> begin
        m = match(r"([^\[\]]+)(?:\[(.+)\])?", b)
        n, i = m[1], m[2]
        v = getfield(a, Symbol(n))
        if isnothing(i)
            v
        else
            #HACK: support indexing of non-Variable (i.e. Vector{Layer})
            try
                v[parse(Int, i)]
            catch
                v[i]
            end
        end
    end, [s, split(n, ".")...])
end

#HACK: swap out state variable of mutable System after initialization
setvar!(s::System, k::Symbol, v) = begin
    setfield!(s, k, v)
    a = Dict(fieldnamesalias(s))[k]
    !isnothing(a) && setfield!(s, a, v)
    nothing
end

#HACK: calculate variable body with external arguments for debugging purpose
value(s::System, k::Symbol; kw...) = begin
    d = dependency(s)
    v = d.M[k]
    @assert v.state in (:Preserve, :Track)
    emit(a) = let p = extractfuncargpair(a), k = p[1]; :($k = $(kw[k])) end
    args = emit.(v.args)
    body = v.body
    eval(:(let $(args...); $body end))
end

import Crayons.Box
Base.show(io::IO, s::System) = print(io, "<$(namefor(s))>")
Base.show(io::IO, ::MIME"text/plain", s::System) = begin
    print(io, "<$(Box.MAGENTA_FG("$(namefor(s))"))>")
    for ((n, a), v) in zip(fieldnamesalias(s), s)
        l = "$(Box.BLUE_FG("$n"))"
        !isnothing(a) && (l *= " $(Box.DARK_GRAY_FG("($a)"))")
        println(io)
        print(io, "  $l $(Box.DARK_GRAY_FG("=")) $v")
    end
end

export System
