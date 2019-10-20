using Cropbox
using Unitful

include("atmosphere/atmosphere.jl")
include("rhizosphere/rhizosphere.jl")
include("phenology/phenology.jl")
include("morphology/morphology.jl")
include("physiology/physiology.jl")

@system Garlic(Plant, Controller) begin
end

o = configure(
    :Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
    :Weather => (:filename => "test/garlic/data/2007.wea"),
    :Phenology => (:planting_date => ZonedDateTime(2007, 11, 1, tz"UTC")),
)
