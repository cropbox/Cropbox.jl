using Cropbox
using SimpleCrop
using Test

using CSV
using DataFrames
using TimeZones

loaddata(f) = CSV.File(joinpath(@__DIR__, "data/simplecrop", f)) |> DataFrame

config = @config (
    :Clock => :step => 1u"d",
    :Calendar => :init => ZonedDateTime(1987, 1, 1, tz"UTC"),
    :Weather => :weather_data => loaddata("weather.csv"),
    :SoilWater => :irrigation_data => loaddata("irrigation.csv"),
)

@testset "simplecrop" begin
    r = simulate(SimpleCrop.Model; config, stop = :endsim)
    visualize(r, :DATE, :LAI; kind = :line) |> display
    visualize(r, :DATE, :(SWC/DP); yunit = u"mm^3/mm^3", kind = :line) |> display
end
