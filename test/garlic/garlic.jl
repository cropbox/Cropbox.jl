module Garlic

using Cropbox

include("atmosphere/atmosphere.jl")
include("rhizosphere/rhizosphere.jl")
include("phenology/phenology.jl")
include("morphology/morphology.jl")
include("physiology/physiology.jl")

end

using TimeZones
garlic = (
    :Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
    :Weather => (:filename => "garlic/data/2007.wea"),
    :Phenology => (:planting_date => ZonedDateTime(2007, 11, 1, tz"UTC")),
)

@testset "garlic" begin
    r = simulate(Garlic.GarlicModel, config=garlic, stop=7000)
    @test r[!, :tick][end] > 7000u"hr"
    Cropbox.plot(r, :tick, [:leaf_mass, :bulb_mass, :total_mass]) |> display
end
