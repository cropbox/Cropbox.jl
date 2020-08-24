module GasExchangeTest

using Cropbox

include("vaporpressure.jl")
include("weather.jl")
include("diffusion.jl")
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
    BoundaryLayer, StomataBase, IntercellularSpace, Irradiance, EnergyBalance
)

@system ModelC3BB(ModelBase, StomataBallBerry, C3, Controller)
@system ModelC4BB(ModelBase, StomataBallBerry, C4, Controller)

@system ModelC3MD(ModelBase, StomataMedlyn, C3, Controller)
@system ModelC4MD(ModelBase, StomataMedlyn, C4, Controller)

end
