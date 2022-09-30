export width, height, maxwidth, minwidth, maxheight, minheight,
       boxsize, hbox, vbox, hskip, vskip, floating, wrap, pad,
       padinner, alignitems, aligncontent, justifycontent, clip,
       container, alignself, floating, flex

for (fn, prop) in [:width => "width",
                   :height => "height",
                   :minwidth => "min-width",
                   :maxwidth => "max-width",
                   :minheight => "min-height",
                   :maxheight => "max-height",
                  ]
    @eval function $fn(val, elem=nothing)
        style(elem, $prop => val)
    end
end

function boxsize(w, h, elem=nothing)
    style(elem, "width"=>w, "height"=>h)
end

function flex(elem=nothing)
    style(elem, "display"=>"flex")
end

function container(xs::AbstractVector)
    dom"div"(xs...)
end

container(xs...) = container([xs...])

"""
    hbox(el...)

    Horizontally align mulitple web components.
"""
function hbox(elems::AbstractVector)
    container(elems)(style("display" => "flex", "flex-direction"=>"row"))
end
hbox(xs...) = hbox([xs...])

"""
    vbox(el...)

    Vertically align mulitple web components.
"""
function vbox(elems::AbstractVector)
    container(elems)(style("display" => "flex", "flex-direction"=>"column"))
end
vbox(xs...) = vbox([xs...])

hskip(x) = boxsize(x, 0px, empty())
vskip(y) = boxsize(0px, y, empty())

function wrap(elem=nothing; reverse=false)
    style(elem, "flex-wrap" => reverse ? "wrap-reverse" : "wrap")
end

function floating(direction, elem=nothing)
    style(elem, float=direction)
end

function justifycontent(justification, elem=nothing)
    style(elem, "justify-content" => justification)
end

function alignitems(alignment, elem=nothing)
    style(elem, "align-items" => alignment)
end

function alignself(alignment, elem=nothing)
    style(elem, "align-self" => alignment)
end

function aligncontent(alignment, elem=nothing)
    style(elem, "align-content" => alignment)
end

function _pad(side::Union{String,Symbol}, length)
    assertoneof(side, ["top", "bottom", "left", "right"], "side")
    "padding-$side" => length
end

function padinner(side::Union{String,Symbol}, length, elem=nothing)
    style(elem, _pad(side, length))
end

function padinner(sides::Union{Vector, Tuple}, length, elem=nothing)
    style(elem, (_pad(side, length) for side in sides)...)
end

function padinner(length, elem=nothing)
    style(elem, "padding" => length)
end

function pad(sides, length, elem)
    padinner(sides, length, container(elem))
end

function pad(length, elem)
    padinner(length, container(elem))
end

function clip(overflow, elem)
    assertoneof(overflow, ["hidden", "visible", "scroll", "auto"], "overflow")
    style(container(elem), "overflow" => overflow)
end
