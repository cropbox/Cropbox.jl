#TODO rename to CarbonAssimilation or so? could be consistently named as CarbonPartition, CarbonAllocation...
@system Photosynthesis begin
    weather ~ hold
    sun ~ hold
    soil ~ hold

    LAI: leaf_area_index ~ hold
    PD: planting_density ~ hold
    water_supply ~ hold
    H2O_weight ~ hold
    CO2_weight ~ hold
    CH2O_weight ~ hold

    radiation(context, sun, leaf_area_index) ~ ::Radiation

    # Calculating transpiration and photosynthesis with stomatal controlled by leaf water potential LeafWP Y
    #TODO: use leaf_nitrogen_content, leaf_width, ET_supply
    sunlit_gasexchange(context, soil, weather, PPFD=Q_sun, LAI=LAI_sunlit) ~ ::GasExchange
    shaded_gasexchange(context, soil, weather, PPFD=Q_sh, LAI=LAI_shaded) ~ ::GasExchange

    leaf_width => begin
        # to be calculated when implemented for individal leaves
        #5.0 # for maize
        1.5 # for garlic
    end ~ preserve(u"cm", parameter)

    #TODO how do we get LeafWP and ET_supply?
    LWP(soil.WP_leaf): leaf_water_potential ~ track(u"MPa")

    evapotranspiration_supply(LAI, PD, ws=water_supply, ww=H2O_weight) => begin
        #TODO common handling logic for zero LAI
        #FIXME check unit conversion (w.r.t water_supply)
        # ? * (1/m^2) / (3600s/hour) / (g/umol) / (cm^2/m^2) = mol/m^2/s H2O
        # ? * (1/m^2) * (hour/3600s) * (umol/g) * (m^2/cm^2) = mol/m^2/s H2O
        # ?(g / hour) * (hour/3600s) * (umol/g) / cm^2
        s = ws * PD / 3600 / ww / LAI
        iszero(LAI) ? zero(s) : s
    end ~ track(u"mol/m^2/s" #= H2O =#)

    LAI_sunlit(radiation.sunlit_leaf_area_index): sunlit_leaf_area_index ~ track
    LAI_shaded(radiation.shaded_leaf_area_index): shaded_leaf_area_index ~ track

    Q_sun(radiation.irradiance_Q_sunlit): sunlit_irradiance ~ track(u"μmol/m^2/s" #= Quanta =#)
    Q_sh(radiation.irradiance_Q_shaded): shaded_irradiance ~ track(u"μmol/m^2/s" #= Quanta =#)

    A_gross(a=sunlit_gasexchange.A_gross_total, b=shaded_gasexchange.A_gross_total): gross_CO2_umol_per_m2_s => begin
        a + b
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    # plantsPerMeterSquare units are umol CO2 m-2 ground s-1
    # in the following we convert to g C plant-1 per hour
    # photosynthesis_gross is umol CO2 m-2 leaf s-1

    A_net(a=sunlit_gasexchange.A_net_total, b=shaded_gasexchange.A_net_total): net_CO2_umol_per_m2_s => begin
        # grams CO2 per plant per hour
        a + b
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    ET(a=sunlit_gasexchange.E_total, b=shaded_gasexchange.E_total): transpiration_H2O_mol_per_m2_s => begin
        #TODO need to save this?
        # when outputting the previous step transpiration is compared to the current step's water uptake
        #self.transpiration_old = self.transpiration
        #FIXME need to check if LAIs are negative?
        #transpiration = sunlit_gasexchange.ET * max(0, sunlit_LAI) + shaded_gasexchange.ET * max(0, shaded_LAI)
        a + b
    end ~ track(u"mmol/m^2/s" #= H2O =#)

    # final values
    assimilation(A_gross, PD, w=CO2_weight) => begin
        # grams CO2 per plant per hour
        A_gross / PD * w
    end ~ track(u"g/d")

    gross_assimilation(A_gross, PD, w=CH2O_weight) => begin
        # grams carbo per plant per hour
        #FIXME check unit conversion between C/CO2 to CH2O
        A_gross / PD * w
    end ~ track(u"g/d")

    net_assimilation(A_net, PD, w=CH2O_weight) => begin
        # grams carbo per plant per hour
        #FIXME check unit conversion between C/CO2 to CH2O
        A_net / PD * w
    end ~ track(u"g/d")

    transpiration(ET, PD, w=H2O_weight) => begin
        # Units of Transpiration from sunlit->ET are mol m-2 (leaf area) s-1
        # Calculation of transpiration from ET involves the conversion to gr per plant per hour
        ET / PD * w
    end ~ track(u"g/d")

    vapor_pressure_deficit(weather.VPD) ~ track(u"kPa")

    conductance(gs_sun=sunlit_gasexchange.gs, LAI_sunlit, gs_sh=shaded_gasexchange.gs, LAI_shaded, LAI) => begin
        #HACK ensure 0 when one of either LAI is 0, i.e., night
        # average stomatal conductance Yang
        c = ((gs_sun * LAI_sunlit) + (gs_sh * LAI_shaded)) / LAI
        #c = max(zero(c), c)
        iszero(LAI) ? zero(c) : c
    end ~ track(u"mol/m^2/s/bar")
end
