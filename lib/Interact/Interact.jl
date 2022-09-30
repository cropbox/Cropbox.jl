module Interact

using Reexport

#HACK: use vendored Interact: https://github.com/JuliaGizmos/Interact.jl/pull/417
include("../Widgets/Widgets.jl")
include("../WebIO/src/WebIO.jl")
include("../CSSUtil/CSSUtil.jl")
include("../JSExpr/JSExpr.jl")
include("../Knockout/Knockout.jl")
include("../InteractBase/InteractBase.jl")

@reexport using .InteractBase
import .InteractBase: notifications
import .Widgets: Widget, @layout, @nodeps
import Observables: @on, @map!, @map

@reexport using OrderedCollections
@reexport using Observables
@reexport using .Knockout
@reexport using .CSSUtil
@reexport using .WebIO
@reexport using .Widgets

struct Bulma<:InteractBase.WidgetTheme; end

const bulma_css = joinpath(@__DIR__, "assets", "bulma.min.css")
const bulma_confined_css = joinpath(@__DIR__, "assets", "bulma_confined.min.css")

function InteractBase.libraries(::Bulma)
    bulmalib = InteractBase.isijulia() ? bulma_confined_css : bulma_css
    vcat(InteractBase.font_awesome, InteractBase.style_css, bulmalib)
end

function __init__()
    InteractBase.registertheme!(:bulma, Bulma())
    settheme!(Bulma())
    nothing
end

end
