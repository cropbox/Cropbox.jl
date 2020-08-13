abstract type Graph end

graph(g::Graph) = g
labels(g::Graph; kw...) = [] #error("labels() not defined for $x")
edgestyles(g::Graph; kw...) = Dict()

makedot(g::Graph) = begin
    node(i, l) = """$i [label="$l"]\n"""
    N = [node(i, l) for (i, l) in enumerate(labels(g))]
    
    edge(a, b) = """$a -> $b [style="$(get(ES, (a, b), ""))"]\n"""
    ES = edgestyles(g)
    E = [edge(e.src, e.dst) for e in edges(graph(g))]
    
    """
    digraph {
    ranksep=0.2
    node[
        width=0
        height=0
        margin=0.03
        shape=plaintext
        fontsize=10
    ]
    edge [
        arrowsize=0.2
        penwidth=0.2
    ]
    $(N...)
    $(E...)
    }
    """
end

writedot(g::Graph) = writedot(tempname(), g)
writedot(name::AbstractString, g::Graph) = begin
    !endswith(name, ".dot") && (name *= ".dot")
    write(name, makedot(g))
    name
end

#TODO: wait until Graphviz_jll adds Windows support
import Conda
writesvg(name::AbstractString, g::Graph) = begin
    !endswith(name, ".svg") && (name *= ".svg")
    dot = writedot(g)
    #HACK: "dot.bat" on Windows
    let ext = (@static Sys.iswindows() ? ".bat" : ""),
        exe = joinpath(Conda.bin_dir(:cropbox), "dot") * ext,
        cmd = `$exe -Tsvg $dot -o $name`
        success(cmd) || error("cannot execute: $cmd")
    end
    name
end

Base.show(io::IO, ::MIME"image/svg+xml", g::Graph) = begin
    f = writesvg(tempname(), g)
    s = read(f, String)
    print(io, s)
end
