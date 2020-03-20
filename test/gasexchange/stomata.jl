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

@system StomataBallBerry(StomataBase) begin
    # Ball-Berry model parameters from Miner and Bauerle 2017, used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
    g0 => 0.017 ~ preserve(u"mol/m^2/s/bar" #= H2O =#, parameter)
    g1 => 4.53 ~ preserve(parameter)

    #HACK: avoid scaling issue with dimensionless unit
    hs(g0, g1, gb, m, A_net, Cs, RH): relative_humidity_at_leaf_surface => begin
        gs = g0 + (g1 * m * (A_net * hs / Cs))
        (hs - RH)*gb ⩵ (1 - hs)*gs
    end ~ solve(lower=0, upper=1) #, u"percent")

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
end

@system StomataMedlyn(StomataBase) begin
    T: leaf_temperature ~ hold

    g0 => 0 ~ preserve(u"mol/m^2/s/bar" #= H2O =#, parameter)
    g1 => 4.0 ~ preserve(u"√kPa", parameter)

    pa(ea=vp.ea, T_air, RH): vapor_pressure_at_air => ea(T_air, RH) ~ track(u"kPa")
    pi(es=vp.es, T): vapor_pressure_at_intercellular_space => es(T) ~ track(u"kPa")
    ps(ps, pa, pi, gb, gs): vapor_pressure_at_leaf_surface => begin
        (ps - pa)*gb ⩵ (pi - ps)*gs
    end ~ bisect(min=0, upper=pi, u"kPa", evalunit=u"mol/m^2/s")
    Ds(ps, pi): vapor_pressure_deficit_at_leaf_surface => begin
        #HACK: prevent zero leading to Inf gs
        max(pi - ps, 1u"Pa")
    end ~ track(u"kPa")

    gs(g0, g1, A_net, Ds, Cs): stomatal_conductance => begin
        g0 + (1 + g1 / sqrt(Ds)) * (A_net / Cs)
    end ~ track(u"mol/m^2/s/bar" #= H2O =#)
end
