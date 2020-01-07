quadratic_solve_upper(a, b, c) = begin
    (a == 0) && return 0.
    v = b^2 - 4a*c
    (v < 0) ? -b/a : (-b + sqrt(v)) / 2a
end
quadratic_solve_lower(a, b, c) = begin
    (a == 0) && return 0.
    v = b^2 - 4a*c
    (v < 0) ? -b/a : (-b - sqrt(v)) / 2a
end

include("c4.jl")
include("boundarylayer.jl")
include("stomata.jl")
include("intercellularspace.jl")
include("irradiance.jl")
include("energybalance.jl")

@system GasExchange(
    WeatherStub, SoilStub,
    BoundaryLayer, Stomata, IntercellularSpace, Irradiance, EnergyBalance,
    C4, Controller
) begin
    #calendar(context) ~ ::Calendar
    weather(context#=, calendar =#) ~ ::Weather
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

df_c = DataFrame(SolRad=1500, CO2=0:10:1500, RH=60, Tair=25, Wind=2.0)
df_t = DataFrame(SolRad=1500, CO2=400, RH=60, Tair=-10:50, Wind=2.0)
df_i = DataFrame(SolRad=0:100:3000, CO2=400, RH=60, Tair=25, Wind=2.0)
df = df_t

config = (
    #:Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
    :Weather => (:dataframe => df, :indexkey => nothing),
    :Soil => :WP_leaf => 2.0,
)

#res = simulate(GasExchange, stop=nrow(df)-2, target=["A_net"], config=config)
#res = simulate(GasExchange, stop=nrow(df)-2, target=[:A_net, :Ac, :Aj, :gs, :Ca, :Ci], index=["context.clock.tick", "weather.CO2", "weather.T_air", "weather.PFD"], config=config, nounit=true)

#config = ()

# config += """
# # Kim et al. (2007), Kim et al. (2006)
# # In von Cammerer (2000), Vpm25=120, Vcm25=60,Jm25=400
# # In Soo et al.(2006), under elevated C5O2, Vpm25=91.9, Vcm25=71.6, Jm25=354.2 YY
# C4.Vpm25 = 70
# C4.Vcm25 = 50
# C4.Jm25 = 300
# C4.Rd25 = 2 # Values in Kim (2006) are for 31C, and the values here are normalized for 25C. SK
# """

# config += """
# [C4]
# # switgrass params from Albaugha et al. (2014)
# # https://doi.org/10.1016/j.agrformet.2014.02.013
# C4.Vpm25 = 52
# C4.Vcm25 = 26
# C4.Jm25 = 145
# """

# config += """
# # switchgrass Vcmax from Le et al. (2010), others multiplied from Vcmax (x2, x5.5)
# C4.Vpm25 = 96
# C4.Vcm25 = 48
# C4.Jm25 = 264
# """

# config += """
# C4.Vpm25 = 100
# C4.Vcm25 = 50
# C4.Jm25 = 200
# """

# config += """
# C4.Vpm25 = 70
# C4.Vcm25 = 50
# C4.Jm25 = 180.8
# """

# config += """
# # switchgrass params from Albaugha et al. (2014)
# C4.Rd25 = 3.6 # not sure if it was normalized to 25 C
# C4.θ = 0.79
# """

# config += """
# # In Sinclair and Horie, Crop Sciences, 1989
# C4.s = 4
# C4.N0 = 0.2
# # In J Vos et al. Field Crop Research, 2005
# C4.s = 2.9
# C4.N0 = 0.25
# # In Lindquist, Weed Science, 2001
# C4.s = 3.689
# C4.N0 = 0.5
# """

# config += """
# # in P. J. Sellers, et al.Science 275, 502 (1997)
# # g0 is b, of which the value for c4 plant is 0.04
# # and g1 is m, of which the value for c4 plant is about 4 YY
# Stomata.g0 = 0.04
# Stomata.g1 = 4.0
# """

# config += """
# # Ball-Berry model parameters from Miner and Bauerle 2017, used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
# Stomata.g0 = 0.017
# Stomata.g1 = 4.53
# """

# config += """
# # calibrated above for our switchgrass dataset
# Stomata.g0 = 0.04
# Stomata.g1 = 1.89
# """

# config += """
# Stomata.g0 = 0.02
# Stomata.g1 = 2.0
# """

# config += """
# # parameters from Le et. al (2010)
# Stomata.g0 = 0.008
# Stomata.g1 = 8.0
# """

# config += """
# # for garlic
# Stomata.g0 = 0.0096
# Stomata.g1 = 6.824
# """

# config += """
# Stomata.sf = 2.3 # sensitivity parameter Tuzet et al. 2003 Yang
# Stomata.ϕf = -1.2 # reference potential Tuzet et al. 2003 Yang
# """

# config += """
# #? = -1.68 # minimum sustainable leaf water potential (Albaugha 2014)
# # switchgrass params from Le et al. (2010)
# Stomata.sf = 6.5
# Stomata.ϕf = -1.3
# """

# config += """
# #FIXME August-Roche-Magnus formula gives slightly different parameters
# # https://en.wikipedia.org/wiki/Clausius–Clapeyron_relation
# VaporPressure.a = 0.61094 # kPa
# VaporPressure.b = 17.625 # C
# VaporPressure.c = 243.04 # C
# """
