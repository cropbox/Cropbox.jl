abstract type Graph end

graph(g::Graph) = g
labels(g::Graph; kw...) = [] #error("labels() not defined for $x")
edgestyles(g::Graph; kw...) = Dict()
graphstyle(g::Graph; kw...) = begin
    d1 = Dict(
        :ratio => 0.5,
        :ranksep => 0.2,
        :margin => 0.03,
        :fontname => "Courier",
        :fontsize => 9,
        :arrowsize => 0.2,
        :penwidth => 0.2,
    )
    d2 = Dict(kw)
    merge(d1, d2)
end

makedot(g::Graph; style=()) = begin
    node(i, l) = """$i [label="$l"]\n"""
    N = [node(i, l) for (i, l) in enumerate(labels(g; style...))]
    
    edge(a, b) = """$a -> $b [style="$(get(ES, (a, b), ""))"]\n"""
    ES = edgestyles(g; style...)
    E = [edge(e.src, e.dst) for e in edges(graph(g))]

    GS = graphstyle(g; style...)
    
    """
    digraph {
    ratio=$(GS[:ratio])
    ranksep=$(GS[:ranksep])
    node[
        width=0
        height=0
        margin=$(GS[:margin])
        shape=plaintext
        fontname=$(GS[:fontname])
        fontsize=$(GS[:fontsize])
    ]
    edge [
        arrowsize=$(GS[:arrowsize])
        penwidth=$(GS[:penwidth])
    ]
    $(N...)
    $(E...)
    }
    """
end

writedot(g::Graph; kw...) = writedot(tempname(), g; kw...)
writedot(name::AbstractString, g::Graph; style=()) = begin
    !endswith(name, ".dot") && (name *= ".dot")
    write(name, makedot(g; style))
    name
end

import Graphviz_jll
writeimage(name::AbstractString, g::Graph; format=nothing, style=()) = begin
    ext = splitext(name)[2]
    if isnothing(format)
        format = ext[2:end]
        isempty(format) && error("format unspecified")
    else
        format = string(format)
        ext != format && (name *= "."*format)
    end
    dot = writedot(g; style)
    cmd = `$(Graphviz_jll.dot()) -T$format $dot -o $name`
    success(cmd) || error("cannot execute: $cmd")
    name
end

Base.show(io::IO, ::MIME"image/svg+xml", g::Graph) = begin
    f = writeimage(tempname(), g; format=:svg)
    s = read(f, String)
    print(io, s)
end
