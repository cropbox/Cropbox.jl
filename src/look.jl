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
    context
    config
    a
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

look(io::IO, ::Union{S,Type{S}}; header=true, doc=true, system=true) where {S<:System} = begin
    print(io, join(filter(!isempty, strip.([
        doc ? buf2str(lookdoc, S; header) : "",
        system ? buf2str(looksystem, S; header) : "",
    ])), "\n\n"))
end
look(io::IO, S::Type{<:System}, k::Symbol; header=true, doc=true, code=true) = begin
    print(io, join(filter(!isempty, strip.([
        doc ? buf2str(lookdoc, S, k; header) : "",
        code ? buf2str(lookcode, S, k; header) : "",
    ])), "\n\n"))
end
look(io::IO, s::S, k::Symbol; header=true, value=true, kw...) where {S<:System} = begin
    print(io, join(filter(!isempty, strip.([
        buf2str(look, S, k; header, kw...),
        value ? buf2str(lookvalue, s, k; header) : "",
    ])), "\n\n"))
end

lookdoc(io::IO, ::Union{S,Type{S}}; header=false) where {S<:System} = begin
    header && printstyled(io, "[doc]\n", color=:light_black)
    try
        #HACK: mimic REPL.doc(b) with no dynamic concatenation
        md = Docs.formatdoc(fetchdocstr(S))
        show(io, MIME("text/plain"), md)
    catch
    end
end
looksystem(io::IO, s::Union{S,Type{S}}; header=false) where {S<:System} = begin
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
end

lookdoc(io::IO, ::Union{S,Type{S}}, k::Symbol; header=false) where {S<:System} = begin
    header && printstyled(io, "[doc]\n", color=:light_black)
    try
        #HACK: mimic REPL.fielddoc(b, k) with no default description
        ds = fetchdocstr(S).data[:fields][k]
        md = ds isa Markdown.MD ? ds : Markdown.parse(ds)
        show(io, MIME("text/plain"), md)
    catch
    end
end
lookcode(io::IO, ::Union{S,Type{S}}, k::Symbol; header=false) where {S<:System} = begin
    header && printstyled(io, "[code]\n", color=:light_black)
    d = dependency(S)
    v = d.M[k]
    Highlights.highlight(io, MIME("text/ansi"), "  " * string(v.line), Highlights.Lexers.JuliaLexer)
end
lookvalue(io::IO, s::System, k::Symbol; header=false) = begin
    header && printstyled(io, "[value]\n", color=:light_black)
    show(io, MIME("text/plain"), s[k])
end

buf2str(f, s, a...; kw...) = buf2str(io -> f(io, s, a...; kw...))
buf2str(f; color=true, kw...) = begin
    d = Dict(:color => color, kw...)
    b = IOBuffer()
    x = IOContext(b, d...)
    f(x)
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

export look, @look
