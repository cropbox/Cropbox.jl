abstract type Graph end

struct GraphLabel
    text::String
end

graphlabel(x; bold=false, italic=false) = begin
    s = replace(string(x), '\\' => "\\\\", '&' => "&amp;", '<' => "&lt;", '>' => "&gt;", '"' => "&quot;", '\n' => "<BR/>")
    italic && (s = "<I>$s</I>")
    bold && (s = "<B>$s</B>")
    GraphLabel(s)
end

graph(g::Graph) = g
labels(g::Graph; kw...) = []
nodeattrs(g::Graph; kw...) = Dict()
edgeattrs(g::Graph; kw...) = Dict()
clusters(g::Graph; kw...) = Pair{String,Vector{Int}}[]
const GRAPH_STYLE_KEYS = (
    :ratio, :rankdir, :ranksep, :nodesep, :splines,
    :margin, :fontname, :fontsize, :arrowsize, :penwidth,
)
stylekeys(::Graph) = GRAPH_STYLE_KEYS
clusterstyle(g::Graph, label; fontname=nothing, fontsize=9, kw...) = (
    label = graphlabel(label; bold=true),
    style = "rounded",
    penwidth = 0.25,
    pencolor = "gray75",
    margin = 10,
    fontname = graphfont(fontname),
    fontsize = fontsize - 1,
    labeljust = :l,
)

graphstyle(g::Graph; ratio=0.5, rankdir=nothing, ranksep=0.2, nodesep=nothing, splines=nothing, kw...) = Dict(
    k => v for (k, v) in pairs((; ratio, ranksep, outputorder=:edgesfirst, rankdir, nodesep, splines))
    if !isnothing(v)
)

graphfont(fontname) = something(fontname, "Courier")

defaultnodeattrs(g::Graph; margin=0.03, fontname=nothing, fontsize=9, kw...) = (
    width = 0,
    height = 0,
    margin = margin,
    shape = :plaintext,
    fontname = graphfont(fontname),
    fontsize = fontsize,
)

defaultedgeattrs(g::Graph; arrowsize=0.2, penwidth=0.2, kw...) = (
    arrowhead = :normal,
    arrowsize = arrowsize,
    penwidth = penwidth,
)

dotescape(x) = replace(string(x), '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n")
dotvalue(x) = "\"$(dotescape(x))\""
dotvalue(x::GraphLabel) = "<$(x.text)>"
dotattrs(d) = isempty(d) ? "" : " [" * join(
    ("$(k)=$(dotvalue(v))" for (k, v) in sort!(collect(pairs(d)); by=p -> string(first(p)))),
    ",",
) * "]"

makedot(g::Graph; style=()) = begin
    unsupported = setdiff(keys(style), stylekeys(g))
    isempty(unsupported) || throw(ArgumentError("unsupported graph style: $(join(unsupported, ", "))"))

    L = labels(g; style...)
    NA = nodeattrs(g; style...)
    EA = edgeattrs(g; style...)
    C = clusters(g; style...)

    node(i) = "$(i)$(dotattrs(merge((label=L[i],), get(NA, i, (;)))))\n"
    clustered = Set(Iterators.flatten(last.(C)))
    N = join(node(i) for i in eachindex(L) if i ∉ clustered)
    B = join(map(enumerate(C)) do (j, (label, I))
        """
        subgraph cluster_$(j) {
        graph$(dotattrs(clusterstyle(g, label; style...)))
        $(join(node.(I)))\
        }
        """
    end)

    E = join("$(e.src) -> $(e.dst)$(dotattrs(get(EA, (e.src, e.dst), (;))))\n" for e in edges(graph(g)))

    """
    digraph {
    graph$(dotattrs(graphstyle(g; style...)))
    node$(dotattrs(defaultnodeattrs(g; style...)))
    edge$(dotattrs(defaultedgeattrs(g; style...)))
    $N$B
    $E
    }
    """
end

"""
    writedot(name::AbstractString, graph::Graph; style=()) -> String
    writedot(graph::Graph; style=()) -> String

Write `graph` as Graphviz DOT source and return the output path. The `.dot`
extension is appended when `name` has no such extension. Omitting `name` writes
to a temporary file.

The `style` named tuple customizes Graphviz generation without changing the
underlying graph. Supported keys are `ratio`, `rankdir`, `ranksep`, `nodesep`,
`splines`, `margin`, `fontname`, `fontsize`, `arrowsize`, and `penwidth`.
Dependency graphs additionally support `alias=true` for declared aliases and
`group=:system` for system clusters. For example:

```julia
g = visualize(GrowingDegree)
Cropbox.writedot("gdd.dot", g; style=(rankdir=:LR, group=:system))
```
"""
writedot(g::Graph; kw...) = writedot(tempname(), g; kw...)
writedot(name::AbstractString, g::Graph; style=()) = begin
    !endswith(name, ".dot") && (name *= ".dot")
    write(name, makedot(g; style))
    name
end

imagefile(name::AbstractString, format) = begin
    ext = splitext(name)[2]
    if isnothing(format)
        format = ext[2:end]
        isempty(format) && error("format unspecified")
    else
        format = string(format)
        ext != "."*format && (name *= "."*format)
    end
    name, format
end

import Graphviz_jll
"""
    writeimage(name::AbstractString, graph::Graph; format=nothing, engine=:dot, style=()) -> String

Render `graph` with Graphviz and return the output path. The output format is
inferred from the extension of `name`, or may be supplied explicitly with
`format`. `engine` selects a Graphviz layout engine such as `:dot`, `:neato`, or
`:sfdp`. The `style` named tuple is forwarded to DOT generation.

```julia
g = visualize(GrowingDegree)
Cropbox.writeimage("gdd.pdf", g)
Cropbox.writeimage("gdd.svg", g; style=(group=:system,))
```

If Graphviz cannot render the requested output, this function reports the
renderer error. [`writedot`](@ref) remains available as a renderer-independent
fallback.
"""
writeimage(name::AbstractString, g::Graph; format=nothing, engine=:dot, style=()) = begin
    name, format = imagefile(name, format)
    dot = writedot(g; style)
    err = IOBuffer()
    try
        cmd = `$(Graphviz_jll.dot()) -K$engine -T$format $dot -o $name`
        run(pipeline(cmd; stdout=devnull, stderr=err))
    catch e
        e isa InterruptException && rethrow()
        detail = strip(String(take!(err)))
        isempty(detail) && (detail = sprint(showerror, e))
        error("Graphviz could not render $format output: $detail")
    finally
        rm(dot; force=true)
    end
    name
end

_showsvg(io::IO, g::Graph; engine=:dot) = begin
    f = tempname() * ".svg"
    try
        writeimage(f, g; engine)
        write(io, read(f))
    catch e
        e isa InterruptException && rethrow()
        print(io, """<svg xmlns="http://www.w3.org/2000/svg" width="720" height="64" viewBox="0 0 720 64">
        <text x="8" y="24" font-family="monospace" font-size="13">Graphviz rendering unavailable</text>
        <text x="8" y="46" font-family="monospace" font-size="11">Use the text display or writedot() fallback.</text>
        </svg>""")
    finally
        rm(f; force=true)
    end
end
Base.show(io::IO, ::MIME"image/svg+xml", g::Graph) = _showsvg(io, g)
