"""
    Cropbox

Declarative crop modeling framework. https://github.com/cropbox/Cropbox.jl

See also: [`@system`](@ref), [`@config`](@ref), [`simulate`](@ref), [`evaluate`](@ref), [`calibrate`](@ref), [`visualize`](@ref), [`manipulate`](@ref)
"""
module Cropbox

include("system.jl")
include("unit.jl")
include("random.jl")
include("graph.jl")
include("macro.jl")
include("state.jl")
include("bundle.jl")
include("config.jl")

include("system/clock.jl")
include("system/context.jl")
include("system/controller.jl")
include("system/calendar.jl")
include("system/store.jl")
include("system/thermaltime.jl")

include("util/simulate.jl")
include("util/calibrate.jl")
include("util/evaluate.jl")
include("util/gather.jl")
include("util/color.jl")
include("util/dive.jl")
include("util/hierarchy.jl")
include("util/plot.jl")
include("util/visualize.jl")
include("util/manipulate.jl")

end
