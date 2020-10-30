#HACK: manually initialize IJulia so it can be picked up by WebIO.__init__
using IJulia
IJulia.init(ARGS)

using Cropbox

@system S(Controller) begin
    a => 1 ~ preserve
    b(a) ~ track
    c(b) ~ accumulate
end
c = @config
r = simulate(S, config=c)
simulate(S, configs=[c])
plot(r, :tick, :c; backend=:UnicodePlots) |> display
plot(r, :tick, :c; backend=:Gadfly)[] |> Cropbox.Gadfly.SVGJS() |> display
plot(r, :tick, :c; kind=:line, backend=:Gadfly)' |> Cropbox.Gadfly.SVG() |> display
visualize(S, :tick, :c; backend=:UnicodePlots) |> display
visualize(S, :tick, :c; backend=:Gadfly)[] |> Cropbox.Gadfly.SVGJS() |> display

using Test

include("../test/state.jl")
include("../test/system.jl")
