using CSV
using DataFrames
using Garlic
using TimeZones

timezone = tz"America/Los_Angeles"
source = Garlic.datapath("CUH/2014.wea")
destination = joinpath(@__DIR__, "cuh_2014_weather.csv")

weather = Garlic.loadwea(source, timezone)
CSV.write(destination, select(weather, :index, :SolRad, :RH, :Tair, :Wind))
