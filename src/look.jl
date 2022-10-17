import Markdown

"""
    look(s[, k])

Look up information about system or variable. Both system type `S` and instance `s` are accepted. For looking up a variable, the name of variable `k` needs to be specified in a symbol.

See also: [`@look`](@ref), [`dive`](@ref)

# Arguments
- `s::Union{System,Type{<:System}}`: target system.
- `k::Symbol`: name of variable.

# Examples
```julia-repl
julia> "my system"
       @system S(Controller) begin
           "a param"
           a => 1 ~ preserve(parameter)
       end;

julia> s = instance(S);

julia> look(s)
[doc]
  my system

[system]
S
  context = <Context>
  config = <Config>
  a = 1.0
julia> look(s, :a)
[doc]
  a param

[code]
  a => 1 ~ preserve(parameter)

[value]
1.0
```

"""

look(a...; kw...) = look(stdout, MIME("text/plain"), a...; kw...)
look(io::IO, m::MIME, a...; kw...) = error("undefined look: $a")

look(m::Module, s::Symbol; kw...) = look(getfield(m, s); kw...)

look(io::IO, m::MIME, s::Union{S,Type{S}}; header=true, doc=true, system=true, kw...) where {S<:System} = begin
    print(io, join(filter!(!isempty, strip.([
        doc ? buf2str(io -> lookdoc(io, m, s; header, kw...)) : "",
        system ? buf2str(io -> looksystem(io, m, s; header, kw...)) : "",
    ])), "\n\n"))
end
look(io::IO, m::MIME, S::Type{<:System}, k::Symbol; header=true, doc=true, code=true, kw...) = begin
    print(io, join(filter!(!isempty, strip.([
        doc ? buf2str(io -> lookdoc(io, m, S, k; header, kw...)) : "",
        code ? buf2str(io -> lookcode(io, m, S, k; header, kw...)) : "",
    ])), "\n\n"))
end
look(io::IO, m::MIME, s::S, k::Symbol; header=true, value=true, kw...) where {S<:System} = begin
    print(io, join(filter!(!isempty, strip.([
        buf2str(io -> look(io, m, S, k; header, kw...)),
        value ? buf2str(io -> lookvalue(io, m, s, k; header, kw...)) : "",
    ])), "\n\n"))
end

lookheader(io::IO, ::MIME, s; header=true, kw...) = begin
    header && printstyled(io, s * "\n", color=:light_black)
end

lookdoc(io::IO, m::MIME, ::Union{S,Type{S}}; header=false, kw...) where {S<:System} = begin
    lookheader(io, m, "[doc]"; header)
    try
        #HACK: mimic REPL.doc(b) with no dynamic concatenation
        md = Docs.formatdoc(fetchdocstr(S))
        show(io, m, md)
    catch
    end
end
looksystem(io::IO, m::MIME"text/plain", s::Union{S,Type{S}}; header=false, kw...) where {S<:System} = begin
    lookheader(io, m, "[system]"; header)
    printstyled(io, namefor(S), color=:light_magenta)
    for (n, a) in fieldnamesalias(S)
        print(io, "\n  ")
        printstyled(io, uncanonicalname(n), color=:light_blue)
        !isnothing(a) && printstyled(io, " (", uncanonicalname(a), ")", color=:light_black)
        s isa Type && continue
        printstyled(io, " = ", color=:light_black)
        print(io, labelstring(s[n]))
    end
end
looksystem(io::IO, m::MIME"text/html", s::Union{S,Type{S}}; header=false, kw...) where {S<:System} = begin
    lookheader(io, m, "[system]"; header)
    println(io, "<table style=\"font-family: monospace\">")
    println(io, "<tr style=\"background-color: transparent\">")
    println(io, "<td colspan=\"4\" style=\"text-align: left; padding: 2px; padding-left: 0px; color: rebeccapurple\">$(namefor(S))</th>")
    println(io, "</tr>")
    for (n, a) in fieldnamesalias(S)
        c1 = uncanonicalname(n)
        c2 = isnothing(a) ? "" : "($(uncanonicalname(a)))"
        c3 = isa(s, Type) ? "" : "="
        c4 = isa(s, Type) ? "" : Markdown.htmlesc(labelstring(s[n]))
        print(io, "<tr style=\"background-color: transparent\">")
        print(io, "<td style=\"text-align: left; padding: 2px; padding-left: 20px; color: royalblue\">$c1</td>")
        print(io, "<td style=\"text-align: left; padding: 2px 0px 2px 0px; color: gray\">$c2</td>")
        print(io, "<td style=\"text-align: center; padding: 2px 10px 2px 10px; color: gray\">$c3</td>")
        print(io, "<td style=\"text-align: left; padding: 2px;\">$c4</td>")
        println(io, "</tr>")
    end
    println(io, "</table>")
end

lookdoc(io::IO, m::MIME, ::Union{S,Type{S}}, k::Symbol; header=false, excerpt=false, kw...) where {S<:System} = begin
    lookheader(io, m, "[doc]"; header)
    #HACK: mimic REPL.fielddoc(b, k) with no default description
    docstr = fetchdocstr(S)
    isnothing(docstr) && return
    n = canonicalname(k, S)
    ds = get(docstr.data[:fields], n, nothing)
    isnothing(ds) && return
    md = ds isa Markdown.MD ? ds : Markdown.parse(ds)
    s = if excerpt
        ts = Markdown.terminline_string(io, md)
        split(strip(ts), '\n')[1] |> Text
    else
        md
    end
    show(io, m, s)
end
lookcode(io::IO, m::MIME, ::Union{S,Type{S}}, k::Symbol; header=false, kw...) where {S<:System} = begin
    lookheader(io, m, "[code]"; header)
    d = dependency(S)
    n = canonicalname(k, S)
    v = d.M[n]
    Highlights.stylesheet(io, m, Highlights.Themes.DefaultTheme)
    Highlights.highlight(io, m, "  " * string(v.line), Highlights.Lexers.JuliaLexer)
end
lookvalue(io::IO, m::MIME, s::System, k::Symbol; header=false, kw...) = begin
    lookheader(io, m, "[value]"; header)
    n = canonicalname(k, s)
    show(io, m, s[n])
end

buf2str(f; color=true, kw...) = begin
    d = Dict(:color => color, kw...)
    b = IOBuffer()
    io = IOContext(b, d...)
    f(io)
    String(take!(b))
end

using MacroTools: @capture

"""
    @look ex
    @look s[, k]

Macro version of `look` supports a convenient way of accessing variable without relying on symbol. Both `@look s.a` and `@look s a` work the same as `look(s, :a)`.

See also: [`look`](@ref)

# Examples
```julia-repl
julia> "my system"
       @system S(Controller) begin
           "a param"
           a => 1 ~ preserve(parameter)
       end;

julia> @look S.a
[doc]
  a param

[code]
  a => 1 ~ preserve(parameter)
```

"""
macro look(ex)
    if @capture(ex, s_.k_(args__))
        f(x) = begin
            if isexpr(x, :parameters)
                x.args
            elseif isexpr(x, :kw)
                [x]
            else
                nothing
            end
        end
        a = filter(x -> !isexpr(x, :parameters, :kw), args)
        kw = filter(!isnothing, f.(args)) |> Iterators.flatten |> collect
        :(Cropbox.value($(esc(s)), $(Meta.quot(k)), $(a...); $(kw...)))
    elseif @capture(ex, s_.k_)
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

getdoc(S::Type{<:System}) = begin
    docstr = fetchdocstr(S)
    isnothing(docstr) && return Markdown.parse("""
    No documentation found.
    
    Type `@look $(scopeof(S)).$(namefor(S))` for more information.
    """)
    b = IOBuffer()
    io = IOContext(b, :color => true)
    println(io, only(docstr.text))
    fields = docstr.data[:fields]
    if !isempty(fields)
        for (n, a) in fieldnamesalias(S)
            !haskey(fields, n) && continue
            ds = get(docstr.data[:fields], n, nothing)
            isnothing(ds) && continue
            entry = isnothing(a) ? "- `$n`" : "- `$n` (`$a`)"
            excerpt = split(strip(ds), '\n')[1]
            println(io, entry * ": " * excerpt)
        end
    end
    String(take!(b)) |> Markdown.parse
end

export look, @look
