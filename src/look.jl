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
look(s::System; kw...) = look(stdout, s; kw...)
look(S::Type{<:System}; kw...) = look(stdout, S; kw...)
look(s::System, k::Symbol; kw...) = look(stdout, s, k; kw...)
look(S::Type{<:System}, k::Symbol; kw...) = look(stdout, S, k; kw...)
look(m::Module, s::Symbol; kw...) = look(getfield(m, s); kw...)

look(io::IO, s::Union{S,Type{S}}; header=true, doc=true, system=true, kw...) where {S<:System} = begin
    print(io, join(filter(!isempty, strip.([
        doc ? buf2str(io -> lookdoc(io, s; header, kw...)) : "",
        system ? buf2str(io -> looksystem(io, s; header, kw...)) : "",
    ])), "\n\n"))
end
look(io::IO, S::Type{<:System}, k::Symbol; header=true, doc=true, code=true, kw...) = begin
    print(io, join(filter(!isempty, strip.([
        doc ? buf2str(io -> lookdoc(io, S, k; header, kw...)) : "",
        code ? buf2str(io -> lookcode(io, S, k; header, kw...)) : "",
    ])), "\n\n"))
end
look(io::IO, s::S, k::Symbol; header=true, value=true, kw...) where {S<:System} = begin
    print(io, join(filter(!isempty, strip.([
        buf2str(io -> look(io, S, k; header, kw...)),
        value ? buf2str(io -> lookvalue(io, s, k; header, kw...)) : "",
    ])), "\n\n"))
end

lookdoc(io::IO, ::Union{S,Type{S}}; header=false, kw...) where {S<:System} = begin
    header && printstyled(io, "[doc]\n", color=:light_black)
    try
        #HACK: mimic REPL.doc(b) with no dynamic concatenation
        md = Docs.formatdoc(fetchdocstr(S))
        show(io, MIME("text/plain"), md)
    catch
    end
end
looksystem(io::IO, s::Union{S,Type{S}}; header=false, kw...) where {S<:System} = begin
    header && printstyled(io, "[system]\n", color=:light_black)
    printstyled(io, namefor(S), color=:light_magenta)
    for (n, a) in fieldnamesalias(S)
        print(io, "\n  ")
        printstyled(io, uncanonicalname(n), color=:light_blue)
        !isnothing(a) && printstyled(io, " (", a, ")", color=:light_black)
        s isa Type && continue
        printstyled(io, " = ", color=:light_black)
        print(io, labelstring(s[n]))
    end
end

lookdoc(io::IO, ::Union{S,Type{S}}, k::Symbol; header=false, excerpt=false, kw...) where {S<:System} = begin
    header && printstyled(io, "[doc]\n", color=:light_black)
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
    show(io, MIME("text/plain"), s)
end
lookcode(io::IO, ::Union{S,Type{S}}, k::Symbol; header=false, kw...) where {S<:System} = begin
    header && printstyled(io, "[code]\n", color=:light_black)
    d = dependency(S)
    n = canonicalname(k, S)
    v = d.M[n]
    Highlights.highlight(io, MIME("text/ansi"), "  " * string(v.line), Highlights.Lexers.JuliaLexer)
end
lookvalue(io::IO, s::System, k::Symbol; header=false, kw...) = begin
    header && printstyled(io, "[value]\n", color=:light_black)
    n = canonicalname(k, s)
    show(io, MIME("text/plain"), s[n])
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

getdoc(S::Type{<:System}) = begin
    docstr = fetchdocstr(S)
    isnothing(docstr) && return Markdown.parse("""
    No documentation found.
    
    Type `@look $(scopeof(S)).$(namefor(S))` for more information.
    """)
    b = IOBuffer()
    io = IOContext(b, :color => true)
    header = false
    doc = true
    look(io, S; header, doc, system=false)
    fields = docstr.data[:fields]
    if !isempty(fields)
        for (n, a) in fieldnamesalias(S)
            !haskey(fields, n) && continue
            println(io, '\n')
            entry = isnothing(a) ? "- `$n`" : "- `$n` (`$a`)"
            show(io, MIME("text/plain"), Markdown.parse(entry))
            print(io, ": ")
            look(io, S, n; header, doc, excerpt=true, code=false)
        end
    end
    String(take!(b)) |> Text
end

export look, @look
