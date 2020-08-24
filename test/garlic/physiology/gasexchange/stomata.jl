@system StomataBase(WeatherStub, SoilStub) begin
    gs: stomatal_conductance ~ hold
    gb: boundary_layer_conductance ~ hold
    A_net: net_photosynthesis ~ hold

    drb: diffusivity_ratio_boundary_layer => 1.37 ~ preserve(#= u"H2O/CO2", =# parameter)
    dra: diffusivity_ratio_air => 1.6 ~ preserve(#= u"H2O/CO2", =# parameter)

    Ca(CO2, P_air): co2_air => (CO2 * P_air) ~ track(u"μbar")
    Cs(Ca, drb, A_net, gb): co2_at_leaf_surface => begin
        Ca - (drb * A_net / gb)
    end ~ track(u"μbar")

    gv(gs, gb): total_conductance_h2o => (gs * gb / (gs + gb)) ~ track(u"mol/m^2/s/bar" #= H2O =#)
    rbc(gb, drb): boundary_layer_resistance_co2 => (drb / gb) ~ track(u"m^2*s/mol*bar")
    rsc(gs, dra): stomatal_resistance_co2 => (dra / gs) ~ track(u"m^2*s/mol*bar")
    rvc(rbc, rsc): total_resistance_co2 => (rbc + rsc) ~ track(u"m^2*s/mol*bar")
end

@system Stomata(StomataBase) begin
    g0 => 0.096 ~ preserve(u"mol/m^2/s/bar" #= H2O =#, parameter)
    g1 => 6.824 ~ preserve(parameter)

    #HACK: avoid scaling issue with dimensionless unit
    hs(g0, g1, gb, m, A_net, Cs, RH): relative_humidity_at_leaf_surface => begin
        gs = g0 + (g1 * m * (A_net * hs / Cs))
        (hs - RH)*gb ⩵ (1 - hs)*gs
    end ~ solve(lower=0, upper=1) #, u"percent")

    gs(g0, g1, m, A_net, hs, Cs): stomatal_conductance => begin
        g0 + (g1 * m * (A_net * hs / Cs))
    end ~ track(u"mol/m^2/s/bar" #= H2O =#, min=g0)

    m: transpiration_reduction_factor => begin
        #TODO: implement soil water module
        1.0
    end ~ track
end
