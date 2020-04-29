@system StomataBase(Weather) begin
    gs: stomatal_conductance ~ hold
    gb: boundary_layer_conductance ~ hold
    A_net: net_photosynthesis ~ hold
    T: leaf_temperature ~ hold

    drb: diffusivity_ratio_boundary_layer => 1.37 ~ preserve(#= u"H2O/CO2", =# parameter)
    dra: diffusivity_ratio_air => 1.6 ~ preserve(#= u"H2O/CO2", =# parameter)

    Ca(CO2, P_air): co2_air => (CO2 * P_air) ~ track(u"μbar")
    Cs(Ca, A_net, gbc): co2_at_leaf_surface => begin
        Ca - A_net / gbc
    end ~ track(u"μbar")

    gv(gs, gb): total_conductance_h2o => (gs * gb / (gs + gb)) ~ track(u"mol/m^2/s/bar" #= H2O =#)

    rbc(gb, drb): boundary_layer_resistance_co2 => (drb / gb) ~ track(u"m^2*s/mol*bar")
    rsc(gs, dra): stomatal_resistance_co2 => (dra / gs) ~ track(u"m^2*s/mol*bar")
    rvc(rbc, rsc): total_resistance_co2 => (rbc + rsc) ~ track(u"m^2*s/mol*bar")

    gbc(rbc): boundary_layer_conductance_co2 => (1 / rbc) ~ track(u"mol/m^2/s/bar")
    gsc(rsc): stomatal_conductance_co2 => (1 / rsc) ~ track(u"mol/m^2/s/bar")
    gvc(rvc): total_conductance_co2 => (1 / rvc) ~ track(u"mol/m^2/s/bar")
end

@system StomataLeafWater begin
    WP_leaf: leaf_water_potential => 0 ~ preserve(u"MPa", parameter)
    Ψv(WP_leaf): bulk_leaf_water_potential ~ track(u"MPa")
    Ψf: reference_leaf_water_potential => -2.0 ~ preserve(u"MPa", parameter)
    sf: stomata_sensitivty_param => 2.3 ~ preserve(u"MPa^-1", parameter)
    fΨv(Ψv, Ψf, sf): stomata_sensitivty => begin
        (1 + exp(sf*Ψf)) / (1 + exp(sf*(Ψf-Ψv)))
    end ~ track
end

@system StomataBallBerry(StomataBase, StomataLeafWater) begin
    # Ball-Berry model parameters from Miner and Bauerle 2017, used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
    g0 => 0.017 ~ preserve(u"mol/m^2/s/bar" #= H2O =#, parameter)
    g1 => 4.53 ~ preserve(parameter)

    #HACK: avoid scaling issue with dimensionless unit
    hs(g0, g1, gb, A_net, Cs, fΨv, RH): relative_humidity_at_leaf_surface => begin
        gs = g0 + g1*(A_net*hs/Cs) * fΨv
        (hs - RH)*gb ⩵ (1 - hs)*gs
    end ~ solve(lower=0, upper=1) #, u"percent")
    Ds(D=vp.D, T, hs): vapor_pressure_deficit_at_leaf_surface => begin
        D(T, hs)
    end ~ track(u"kPa")

    gs(g0, g1, A_net, hs, Cs, fΨv): stomatal_conductance => begin
        gs = g0 + g1*(A_net*hs/Cs) * fΨv
        max(gs, g0)
    end ~ track(u"mol/m^2/s/bar" #= H2O =#)
end

@system StomataMedlyn(StomataBase, StomataLeafWater) begin
    g0 => 0.02 ~ preserve(u"mol/m^2/s/bar" #= H2O =#, parameter)
    g1 => 4.0 ~ preserve(u"√kPa", parameter)

    pa(ea=vp.ea, T_air, RH): vapor_pressure_at_air => ea(T_air, RH) ~ track(u"kPa")
    pi(es=vp.es, T): vapor_pressure_at_intercellular_space => es(T) ~ track(u"kPa")
    ps(Ds, pi): vapor_pressure_at_leaf_surface => (pi - Ds) ~ track(u"kPa")
    Ds¹ᐟ²(g0, g1, gb, A_net, Cs, fΨv, pi, pa) => begin
        #HACK: SymPy couldn't extract polynomial coeffs for ps inside √
        gs = g0 + (1 + g1 / Ds¹ᐟ²) * (A_net / Cs) * fΨv
        ps = pi - Ds¹ᐟ²^2
        (ps - pa)*gb ⩵ (pi - ps)*gs
    end ~ solve(lower=0, upper=√pi', u"√kPa")
    Ds(Ds¹ᐟ²): vapor_pressure_deficit_at_leaf_surface => max(Ds¹ᐟ²^2, 1u"Pa") ~ track(u"kPa")
    hs(RH=vp.RH, T, Ds): relative_humidity_at_leaf_surface => RH(T, Ds) ~ track

    gs(g0, g1, A_net, Ds, Cs, fΨv): stomatal_conductance => begin
        gs = g0 + (1 + g1/√Ds)*(A_net/Cs) * fΨv
        max(gs, g0)
    end ~ track(u"mol/m^2/s/bar" #= H2O =#)
end
