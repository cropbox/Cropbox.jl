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
    LAI: leaf_area_index ~ track(override)

    A_net_total(A_net, LAI): net_photosynthesis_total => A_net * LAI ~ track(u"μmol/m^2/s" #= CO2 =#)
    A_gross_total(A_gross, LAI): gross_photosynthesis_total => A_gross * LAI ~ track(u"μmol/m^2/s" #= CO2 =#)
    E_total(E, LAI): transpiration_total => E * LAI ~ track(u"mmol/m^2/s" #= H2O =#)

    #TODO: nitrogen response not implemented for C3 yet
    #N: nitrogen => 2.0 ~ preserve(parameter)
end
