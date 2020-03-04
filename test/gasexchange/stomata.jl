@system Stomata(WeatherStub, SoilStub) begin
    gb: boundary_layer_conductance ~ hold
    A_net: net_photosynthesis ~ hold

    # Ball-Berry model parameters from Miner and Bauerle 2017, used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
    g0 => 0.017 ~ preserve(u"mol/m^2/s/bar" #= H2O =#, parameter)
    g1 => 4.53 ~ preserve(parameter)

    drb: diffusivity_ratio_boundary_layer => 1.37 ~ preserve(#= u"H2O/CO2", =# parameter)
    dra: diffusivity_ratio_air => 1.6 ~ preserve(#= u"H2O/CO2", =# parameter)

    Ca(CO2, P_air): co2_air => (CO2 * P_air) ~ track(u"μbar")
    # surface CO2 in mole fraction
    Cs(Ca, drb, A_net, gb): co2_at_leaf_surface => begin
        Ca - (drb * A_net / gb)
        # gamma: 10.0 for C4 maize
        #max(Cs, gamma)
    end ~ track(u"μbar")

    #HACK: avoid scaling issue with dimensionless unit
    hs(g0, g1, gb, m, A_net, Cs, RH): relative_humidity_at_leaf_surface => begin
        gs = g0 + (g1 * m * (A_net * hs / Cs))
        (hs - RH)*gb ⩵ (1 - hs)*gs
    end ~ solve(lower=0, upper=1) #, u"percent")

    # stomatal conductance for water vapor in mol m-2 s-1
    gs(g0, g1, m, A_net, hs, Cs): stomatal_conductance => begin
        gs = g0 + (g1 * m * (A_net * hs / Cs))
        max(gs, g0)
    end ~ track(u"mol/m^2/s/bar" #= H2O =#)

    LWP(WP_leaf): leaf_water_potential ~ track(u"MPa")
    sf => 2.3 ~ preserve(u"MPa^-1", parameter)
    ϕf => -2.0 ~ preserve(u"MPa", parameter)
    m(LWP, sf, ϕf): transpiration_reduction_factor => begin
        (1 + exp(sf * ϕf)) / (1 + exp(sf * (ϕf - LWP)))
    end ~ track

    gv(gs, gb): total_conductance_h2o => begin
        gs * gb / (gs + gb)
    end ~ track(u"mol/m^2/s/bar" #= H2O =#)

    rbc(gb, drb): boundary_layer_resistance_co2 => begin
        drb / gb
    end ~ track(u"m^2*s/mol*bar")

    rsc(gs, dra): stomatal_resistance_co2 => begin
        dra / gs
    end ~ track(u"m^2*s/mol*bar")

    rvc(rbc, rsc): total_resistance_co2 => begin
        rbc + rsc
    end ~ track(u"m^2*s/mol*bar")
end