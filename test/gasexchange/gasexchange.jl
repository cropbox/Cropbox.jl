module GasExchangeTest

using Cropbox

include("vaporpressure.jl")
include("weather.jl")
include("soil.jl")

include("c3.jl")
include("c4.jl")
include("boundarylayer.jl")
include("stomata.jl")
include("intercellularspace.jl")
include("irradiance.jl")
include("energybalance.jl")
include("transpiration.jl")

@system ModelBase(
    WeatherStub, SoilStub,
    BoundaryLayer, Stomata, IntercellularSpace, Irradiance, EnergyBalance, Transpiration
) begin
    weather(context) ~ ::Weather
    soil(context) ~ ::Soil

    #HACK: should be PPFD from Radiation
    PPFD(weather.PFD): photosynthetic_photon_flux_density ~ track(u"μmol/m^2/s")

    N: nitrogen => 2.0 ~ preserve(parameter)
end

@system C3Model(ModelBase, C3, Controller)
@system C4Model(ModelBase, C4, Controller)

estimate(M, df; config=(),
    index=[:CO2, :PFD, :T_air],
    target=[:A_net, :Ac, :Aj, :gs, :Ci, :Ca]
) = simulate(M, stop=nrow(df)-2, config=[(
    :Weather => (:dataframe => df, :indexkey => nothing),
    :Soil => :WP_leaf => 2.0,
), config], index=index, target=target)

estimate_c3(df; kw...) = estimate(C3Model, df; kw...)
estimate_c4(df; kw...) = estimate(C4Model, df; kw...)

end
