abstract type Graph end

graph(g::Graph) = g
labels(g::Graph; kw...) = [] #error("labels() not defined for $x")
edgestyles(g::Graph; kw...) = Dict()

import TikzGraphs
plot(g::Graph, layout=(), label=(), edgestyle=()) = begin
    TikzGraphs.plot(
        graph(g),
        TikzGraphs.Layouts.Layered(; layout...),
        labels(g; label...);
        edge_styles=edgestyles(g; edgestyle...),
        prepend_preamble="\\usetikzlibrary{backgrounds}",
        options="background rectangle/.style={fill=white}, show background rectangle",
    )
end

import TikzPictures
Base.write(filename::AbstractString, g::Graph; plotopts...) = begin
    f = TikzPictures.PDF(string(filename))
    TikzPictures.save(f, plot(g; plotopts...))
end
