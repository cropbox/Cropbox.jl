export border, borderstyle, bordercolor, borderwidth, hline, vline,
       fontweight, background


# TODO: add more background features
# maybe a way to load images?
function background(spec, elem=nothing)
    style(elem, "background" => spec)
end

function _border_prefix(side::Union{Symbol, String})
    assertoneof(side, ["top", "bottom", "left", "right"], "side")
    "border$(uppercasefirst(side))"
end

function assertstyle(style)
    assertoneof(style, ["solid", "dotted", "dashed", "none"], "border style")
end

function border(side::Union{Symbol, String}, styl, width, color, elem=nothing)
    assertstyle(styl)
    style(elem, _border_prefix(side) => "$styl $(JSON.lower(width)) $(JSON.lower(parse(Colorant, color)))")
end

function border(sides::AbstractArray, args...)
    x = border(sides[1], args...)
    for i = 2:length(sides)
        x = border(sides[i], args...)
    end
    x
end

function borderstyle(side::Union{Symbol, String}, styl, elem=nothing)
    assertstyle(styl)
    style(elem, _border_prefix(side) * "Style" => styl)
end

function bordercolor(side::Union{Symbol, String}, color, elem=nothing)
    style(elem, _border_prefix(side) * "Color" => color)
end

function borderwidth(side::Union{Symbol, String}, width, elem=nothing)
    style(elem, _border_prefix(side) * "Width" => width)
end

"""
    hline()

    Draw a horizonal line.

Keyword Arguments:
=================
 - style: Indicates whether line should be solid or dotted.
Defaults to "solid"
- w: Specifies line width. Defaults to 1px
- color: specifies color in hex code RGB. Defaults to "#dedede".
"""
function hline(; style="solid", w=1px, color="#dedede")
    border("bottom", style, w, color, alignself("stretch", empty()))
end

"""
    vline()

    Draw a vertical line.

Keyword Arguments:
=================
 - style: Indicates whether line should be solid or dotted.
Defaults to "solid"
- w: Specifies line width. Defaults to 1px
- color: specifies color in hex code RGB. Defaults to "#dedede".
"""
function vline(; style="solid", w=1px, color="#dedede")
    border("left", style, w, color, alignself("stretch", empty()))
end

function fontweight(weight, elem=nothing)
    style(elem, "fontWeight" => weight)
end
