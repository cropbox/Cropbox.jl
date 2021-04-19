using Cropbox

@system S(Controller) begin
    a => 1 ~ preserve
    b(a) ~ track
    c(b) ~ accumulate
end
c = @config
r = simulate(S, config=c)
simulate(S, configs=[c])
visualize(r, :time, :c; backend=:UnicodePlots) |> display
visualize(r, :time, :c; backend=:Gadfly)[] |> Cropbox.Gadfly.SVGJS() |> display
visualize(r, :time, :c; kind=:line, backend=:Gadfly)' |> Cropbox.Gadfly.SVG() |> display
visualize(S, :time, :c; backend=:UnicodePlots) |> display
visualize(S, :time, :c; backend=:Gadfly)[] |> Cropbox.Gadfly.SVGJS() |> display
r |> display
display(MIME("text/html"), r)

using Test

include("../test/state.jl")
include("../test/system.jl")
