module CSSUtil

using WebIO
using JSON
import WebIO: render

export style
export @md_str

using Measures
using Colors

function style(dict::Dict)
    Dict(:style=>dict)
end

function style(p::Pair...)
    style(Dict(p...))
end

"""
When a Node's `instanceof` field is set to `Fallthrough()`
it renders it only child and places it in place of itself
("splat"s its children with the Node's own siblings)

This is useful when you want to defer rendering an object
till its parents have been rendered
"""
struct Fallthrough
end

wrapnode(n::Node) = n
wrapnode(x) = node(Fallthrough(), x)

function render(n::Node{Fallthrough})
    inner = render(first(children(n)))
    inner isa String ? inner : inner(props(n))
end

JSON.lower(n::Node{Fallthrough}) = JSON.lower(render(n))

function style(elem, dict::Dict)
    wrapnode(elem)(style(dict))
end

function style(elem, p::Pair...)
    wrapnode(elem)(style(p...))
end

function style(::Nothing, arg::Pair...)
    style(arg...)
end

function style(::Nothing, arg::Dict)
    style(arg)
end

empty() = dom"div"()

export mm, em, cm, inch, pt, px, vw, vh, vmin, cent
"1mm"
const mm = Length(:mm, 1.0)
" 1em "
const em = Length(:em, 1.0)
"1cm"
const cm = Length(:cm, 1.0)
"1inch"
const inch = Length(:in, 1.0)
"1pt"
const pt = Length(:pt, 1.0)
"1px"
const px = Length(:px, 1.0)
"1vw"
const vw = Length(:vw, 1.0)
"1vh"
const vh = Length(:vh, 1.0)
"1vmin"
const vmin = Length(:vmin, 1.0)
"1% length"
const cent = Length(:cent, 1.0)

JSON.lower(l::Length{u}) where {u} = "$(l.value)$u"
JSON.lower(l::Length{:cent}) = "$(l.value)%"
JSON.lower(c::Color) = "#$(hex(c))"

function assertoneof(x, xs, name="argument")
    if !(string(x) in xs)
        throw(ArgumentError("$name should be one of $(join(xs, ",", "or")) as a string or symbol."))
    end
end

include("layout.jl")
include("theme.jl")
include("markdown.jl")

end # module
