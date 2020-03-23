include("c3.jl")
include("boundarylayer.jl")
include("stomata.jl")
include("intercellularspace.jl")
include("irradiance.jl")
include("energybalance.jl")

@system GasExchange(
    WeatherStub, SoilStub,
    BoundaryLayer, Stomata, IntercellularSpace, Irradiance, EnergyBalance,
    C3
) begin
    weather ~ ::Weather(override)
    soil ~ ::Soil(override)

    #FIXME: confusion between PFD vs. PPFD
    PPFD: photosynthetic_photon_flux_density ~ track(u"μmol/m^2/s" #= Quanta =#, override)

    #TODO: nitrogen response not implemented for C3 yet
    #N: nitrogen => 2.0 ~ preserve(parameter)
end
