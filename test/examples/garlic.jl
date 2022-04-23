using Cropbox
using Garlic
using Test

@testset "garlic" begin
    r = simulate(Garlic.Model;
        config=Garlic.Examples.AoB.KM_2014_P2_SR0,
        stop="calendar.count",
        snap=s -> Dates.hour(s.calendar.time') == 12,
    )
    @test r.leaves_initiated[end] > 0
    visualize(r, :DAP, [:leaves_appeared, :leaves_mature, :leaves_dropped], kind=:step) |> println # Fig. 3.D
    visualize(r, :DAP, :green_leaf_area) |> println # Fig. 4.D
    visualize(r, :DAP, [:leaf_mass, :bulb_mass, :total_mass]) |> println
end
