using Cropbox
using Dates
using Garlic
using Test
using TimeZones

@testset "garlic" begin
    timezone = tz"America/Los_Angeles"
    weather_path = joinpath(@__DIR__, "data/garlic/cuh_2014_weather.csv")
    weather_columns = [
        Dict("name" => "index", "type" => "ZonedDateTime", "timezone" => string(timezone)),
        Dict("name" => "SolRad", "type" => "Float64", "unit" => "W/m^2"),
        Dict("name" => "RH", "type" => "Float64", "unit" => "percent"),
        Dict("name" => "Tair", "type" => "Float64", "unit" => "°C"),
        Dict("name" => "Wind", "type" => "Float64", "unit" => "m/s"),
    ]
    base_config = @config(
        Garlic.Examples.AoB.KM,
        Garlic.Examples.AoB.CUH,
        Garlic.Examples.AoB.P2,
        (
            :Calendar => (
                init = ZonedDateTime(2014, 9, 1, 1, timezone),
                last = ZonedDateTime(2015, 7, 7, timezone),
            ),
            :Meta => (year = 2014,),
            :Phenology => (
                storage_days = 143,
                planting_date = ZonedDateTime(2014, 11, 20, timezone),
                emergence_date = ZonedDateTime(2014, 12, 30, timezone),
                scape_removal_date = nothing,
            ),
        ),
    )
    request = Dict(
        "config_entries" => [
            Dict(
                "path" => "Weather.s",
                "value" => Dict(
                    "type" => "CSV",
                    "filename" => basename(weather_path),
                    "content" => read(weather_path, String),
                    "columns" => weather_columns,
                ),
            ),
        ],
    )
    weather_config = Cropbox.normalize_request(Garlic.Model, request)["config"]
    config = Cropbox.configure(base_config, weather_config)

    r = simulate(Garlic.Model;
        config,
        stop="calendar.count",
        snap=s -> Dates.hour(s.calendar.time') == 12,
    )
    @test r.leaves_initiated[end] > 0
    visualize(r, :DAP, [:leaves_appeared, :leaves_mature, :leaves_dropped], kind=:step) |> println # Fig. 3.D
    visualize(r, :DAP, :green_leaf_area) |> println # Fig. 4.D
    visualize(r, :DAP, [:leaf_mass, :bulb_mass, :total_mass]) |> println
end
