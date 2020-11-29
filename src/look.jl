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

using MacroTools: @capture

macro look(ex)
    if @capture(ex, s_.k_)
        :(Cropbox.look($(esc(s)), $(Meta.quot(k))))
    else
        :(Cropbox.look($(esc(ex))))
    end
end

macro look(s, k)
    :(Cropbox.look($(esc(s)), $(Meta.quot(k))))
end

fetchdocstr(S::Type{<:System}) = begin
    b = Docs.Binding(scopeof(S), nameof(typefor(S)))
    for m in Docs.modules
        d = Docs.meta(m)
        haskey(d, b) && return d[b].docs[Union{}]
    end
    nothing
end

export look, @look
