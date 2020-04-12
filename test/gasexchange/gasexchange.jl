module GasExchangeTest

using Cropbox

include("vaporpressure.jl")
include("weather.jl")
include("nitrogen.jl")
include("base.jl")
include("c3.jl")
include("c4.jl")
include("boundarylayer.jl")
include("stomata.jl")
include("intercellularspace.jl")
include("irradiance.jl")
include("energybalance.jl")

@system ModelBase(
    Weather, Nitrogen,
    BoundaryLayer, StomataBallBerry, IntercellularSpace, Irradiance, EnergyBalance
)

@system C3Model(ModelBase, C3, Controller)
@system C4Model(ModelBase, C4, Controller)

end
