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

@system Model(
    WeatherStub, SoilStub,
    BoundaryLayer, Stomata, IntercellularSpace, Irradiance, EnergyBalance,
    C4, Controller
) begin
    weather(context) ~ ::Weather
    soil(context) ~ ::Soil

    #HACK: should be PPFD from Radiation
    PPFD(weather.PFD): photosynthetic_photon_flux_density ~ track(u"μmol/m^2/s")

    N: nitrogen => 2.0 ~ preserve(parameter)

    ET(gv, T, T_air, P_air, RH, ea=weather.vp.ambient, es=weather.vp.saturation): evapotranspiration => begin
        Es = es(T)
        Ea = ea(T_air, RH)
        ET = gv * ((Es - Ea) / P_air) / (1 - (Es + Ea) / P_air) * P_air
        max(ET, zero(ET)) # 04/27/2011 dt took out the 1000 everything is moles now
    end ~ track(u"mmol/m^2/s" #= H2O =#)
end

estimate(df; config=(),
    index=[:CO2, :PFD, :T_air],
    target=[:A_net, :Ac, :Aj, :gs, :Ci, :Ca]
) = simulate(Model, stop=nrow(df)-2, config=[(
    :Weather => (:dataframe => df, :indexkey => nothing),
    :Soil => :WP_leaf => 2.0,
), config], index=index, target=target)

end
