abstract type System end

namefor(s::S) where {S<:System} = namefor(S)
namefor(S) = nameof(S)
typefor(s::S) where {S<:System} = S
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

Base.getproperty(s::System, n::AbstractString) = begin
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
Base.show(io::IO, ::MIME"text/plain", s::System) = look(io, s; doc=false, header=false, endnewline=false)

import Markdown

look(s::System; kw...) = look(stdout, s; kw...)
look(S::Type{<:System}; kw...) = look(stdout, S; kw...)
look(s::System, k::Symbol; kw...) = look(stdout, s, k; kw...)
look(S::Type{<:System}, k::Symbol; kw...) = look(stdout, S, k; kw...)

look(io::IO, s::Union{S,Type{S}}; doc=true, header=true, endnewline=true, kw...) where {S<:System} = begin
    doc && try
        #HACK: mimic REPL.doc(b) with no dynamic concatenation
        md = Docs.formatdoc(fetchdocstr(S))
        header && printstyled(io, "[doc]\n", color=:light_black)
        show(io, MIME("text/plain"), md)
        println(io)
        println(io, "")
    catch
    end
    header && printstyled(io, "[system]\n", color=:light_black)
    printstyled(io, namefor(S), color=:light_magenta)
    for (n, a) in fieldnamesalias(S)
        print(io, "\n  ")
        printstyled(io, n, color=:light_blue)
        !isnothing(a) && printstyled(io, " (", a, ")", color=:light_black)
        s isa Type && continue
        printstyled(io, " = ", color=:light_black)
        print(io, labelstring(s[n]))
    end
    endnewline && println(io)
    nothing
end
look(io::IO, s::S, k::Symbol; header=true, endnewline=true, kw...) where {S<:System} = begin
    look(io, S, k; header, endnewline, kw...)
    println(io, "")
    printstyled(io, "[value]\n", color=:light_black)
    show(io, MIME("text/plain"), s[k])
    endnewline && println(io)
    nothing
end
look(io::IO, S::Type{<:System}, k::Symbol; doc=true, header=true, endnewline=true, kw...) = begin
    doc && try
        #HACK: mimic REPL.fielddoc(b, k) with no default description
        ds = fetchdocstr(S).data[:fields][k]
        md = ds isa Markdown.MD ? ds : Markdown.parse(ds)
        printstyled(io, "[doc]\n", color=:light_black)
        show(io, MIME("text/plain"), md)
        println(io)
        println(io, "")
    catch
    end
    d = dependency(S)
    v = d.M[k]
    printstyled(io, "[code]\n", color=:light_black)
    Highlights.highlight(io, MIME("text/ansi"), "  " * string(v.line), Highlights.Lexers.JuliaLexer)
    endnewline && println(io)
    nothing
end

fetchdocstr(S::Type{<:System}) = begin
    b = Docs.Binding(scopeof(S), nameof(typefor(S)))
    for m in Docs.modules
        d = Docs.meta(m)
        haskey(d, b) && return d[b].docs[Union{}]
    end
    nothing
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
