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

Base.show(io::IO, s::System) = print(io, "<$(namefor(s))>")
Base.show(io::IO, ::MIME"text/plain", s::System) = begin
    printstyled(io, namefor(s), color=:magenta)
    for ((n, a), v) in zip(fieldnamesalias(s), s)
        print(io, "\n  ")
        printstyled(io, n, color=:blue)
        !isnothing(a) && printstyled(io, " (", a, ")", color=:light_black)
        printstyled(io, " = ", color=:light_black)
        print(io, labelstring(v))
    end
end

look(s::System) = look(stdout, s)
look(S::Type{<:System}) = look(stdout, S)
look(s::System, k::Symbol) = look(stdout, s, k)
look(S::Type{<:System}, k::Symbol) = look(stdout, S, k)

look(io::IO, s::System) = show(io, MIME("text/plain"), s)
look(io::IO, S::Type{<:System}) = begin
    printstyled(io, namefor(S), color=:magenta)
    for (n, a) in fieldnamesalias(S)
        print(io, "\n  ")
        printstyled(io, n, color=:blue)
        !isnothing(a) && printstyled(io, " (", a, ")", color=:light_black)
    end
end
look(io::IO, s::S, k::Symbol) where {S<:System} = begin
    look(io, S, k)
    show(io, MIME("text/plain"), s[k])
    println(io)
end
look(io::IO, S::Type{<:System}, k::Symbol) = begin
    d = dependency(S)
    v = d.M[k]
    println(io, "----")
    Highlights.highlight(io, MIME("text/ansi"), string(v.line) * '\n', Highlights.Lexers.JuliaLexer)
    println(io, "----")
end

labelstring(v; maxlength=nothing) = begin
    l = repr(v; context=IOContext(devnull, :compact => true, :limit => true))
    n = length(l)
    i = findfirst('\n', l)
    i = isnothing(i) ? n : i-1
    x = isnothing(maxlength) ? n : maxlength
    i = min(i, x)
    i < n ? l[1:i] * "…" : l
end

export System
export look
