include("gasexchange.jl")

"""
Kim et al. (2007), Kim et al. (2006)
In von Cammerer (2000), Vpm25=120, Vcm25=60,Jm25=400
In Soo et al.(2006), under elevated C5O2, Vpm25=91.9, Vcm25=71.6, Jm25=354.2 YY
"""
ge_maize = :C4 => (
    Vpm25 = 70, Vcm25 = 50, Jm25 = 300,
    Rd25 = 2, # Values in Kim (2006) are for 31C, and the values here are normalized for 25C. SK
)

"""
switgrass params from Albaugha et al. (2014)
https://doi.org/10.1016/j.agrformet.2014.02.013
"""
ge_switchgrass1 = :C4 => (Vpm25 = 52, Vcm25 = 26, Jm25 = 145)

"""
switchgrass Vcmax from Le et al. (2010),
others multiplied from Vcmax (x2, x5.5)
"""
ge_switchgrass2 = :C4 => (Vpm25 = 96, Vcm25 = 48, Jm25 = 264)

ge_switchgrass3 = :C4 => (Vpm25 = 100, Vcm25 = 50, Jm25 = 200)
ge_switchgrass4 = :C4 => (Vpm25 = 70, Vcm25 = 50, Jm25 = 180.8)

"switchgrass params from Albaugha et al. (2014)"
ge_switchgrass_base = :C4 => (
    Rd25 = 3.6, # not sure if it was normalized to 25 C
    θ = 0.79,
)

"In Sinclair and Horie, Crop Sciences, 1989"
ge_nitrogen1 = :C4 => (s = 4, N0 = 0.2)

"In J Vos et al. Field Crop Research, 2005"
ge_nitrogen2 = :C4 => (s = 2.9, N0 = 0.25)

"In Lindquist, Weed Science, 2001"
ge_nitrogen3 = :C4 => (s = 3.689, N0 = 0.5)

"""
in P. J. Sellers, et al.Science 275, 502 (1997)
g0 is b, of which the value for c4 plant is 0.04
and g1 is m, of which the value for c4 plant is about 4 YY
"""
ge_stomata1 = :Stomata => (g0 = 0.04, g1 = 4.0)

"""
Ball-Berry model parameters from Miner and Bauerle 2017,
used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
"""
ge_stomata2 = :Stomata => (g0 = 0.017, g1 = 4.53)

"calibrated above for our switchgrass dataset"
ge_stomata3 = :Stomata => (g0 = 0.04, g1 = 1.89)
ge_stomata4 = :Stomata => (g0 = 0.02, g1 = 2.0)

"parameters from Le et. al (2010)"
ge_stomata5 = :Stomata => (g0 = 0.008, g1 = 8.0)

"for garlic"
ge_stomata6 = :Stomata => (g0 = 0.0096, g1 = 6.824)

ge_water1 = :Stomata => (
    sf = 2.3, # sensitivity parameter Tuzet et al. 2003 Yang
    ϕf = -1.2, # reference potential Tuzet et al. 2003 Yang
)

"switchgrass params from Le et al. (2010)"
ge_water2 = :Stomata => (
    #? = -1.68, # minimum sustainable leaf water potential (Albaugha 2014)
    sf = 6.5,
    ϕf = -1.3,
)

"""
August-Roche-Magnus formula gives slightly different parameters
https://en.wikipedia.org/wiki/Clausius–Clapeyron_relation
"""
ge_vaporpressure1 = :VaporPressure => (
    a = 0.61094, # kPa
    b = 17.625, # C
    c = 243.04, # C
)

using DataFrames
#HACK: zero CO2 prevents convergence of bisection method
ge_df_c = DataFrame(SolRad=1500, CO2=1:1:1500, RH=60, Tair=25, Wind=2.0)
ge_df_q = DataFrame(SolRad=0:1:3000, CO2=400, RH=60, Tair=25, Wind=2.0)
ge_df_t = DataFrame(SolRad=1500, CO2=400, RH=60, Tair=-10:0.1:50, Wind=2.0)

@testset "gasexchange" begin
    # visualize(r, i, t, t0=[:A_net]) = begin
    #     #HACK: ensure plot range is around A_net
    #     p = Cropbox.plot(r, i, t0)
    #     Cropbox.plot!(p, r, i, t) |> display
    # end    
    visualize(r, i, t) = Cropbox.plot(r, i, t) |> display

    @testset "C3" begin
        estimate = GasExchangeTest.estimate_c3
        target = [:A_net, :Ac, :Aj, :Ap]

        @testset "A-Ci" begin
            r = estimate(ge_df_c)
            visualize(r, :Ci, target)
        end

        @testset "A-Q" begin
            r = estimate(ge_df_q)
            visualize(r, :PFD, target)
        end

        @testset "A-T" begin
            r = estimate(ge_df_t)
            visualize(r, :T_air, target)
        end
    end

    @testset "C4" begin
        estimate = GasExchangeTest.estimate_c4
        target = [:A_net, :Ac, :Aj]

        @testset "A-Ci" begin
            r = estimate(ge_df_c)
            visualize(r, :Ci, target)
        end

        @testset "A-Q" begin
            r = estimate(ge_df_q)
            visualize(r, :PFD, target)
        end

        @testset "A-T" begin
            r = estimate(ge_df_t)
            visualize(r, :T_air, target)
        end
    end
end
