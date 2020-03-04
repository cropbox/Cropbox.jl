module GasExchangeTest

using Cropbox

include("vaporpressure.jl")
include("weather.jl")
include("soil.jl")

include("c4.jl")
include("boundarylayer.jl")
include("stomata.jl")
include("intercellularspace.jl")
include("irradiance.jl")
include("energybalance.jl")
include("transpiration.jl")

@system Model(
    WeatherStub, SoilStub,
    BoundaryLayer, Stomata, IntercellularSpace, Irradiance, EnergyBalance,
    BoundaryLayer, Stomata, IntercellularSpace, Irradiance, EnergyBalance, Transpiration,
    C4, Controller
) begin
    weather(context) ~ ::Weather
    soil(context) ~ ::Soil

    #HACK: should be PPFD from Radiation
    PPFD(weather.PFD): photosynthetic_photon_flux_density ~ track(u"μmol/m^2/s")

    N: nitrogen => 2.0 ~ preserve(parameter)
end

estimate(df; config=(),
    index=[:CO2, :PFD, :T_air],
    target=[:A_net, :Ac, :Aj, :gs, :Ci, :Ca]
) = simulate(Model, stop=nrow(df)-2, config=[(
    :Weather => (:dataframe => df, :indexkey => nothing),
    :Soil => :WP_leaf => 2.0,
), config], index=index, target=target)

end
