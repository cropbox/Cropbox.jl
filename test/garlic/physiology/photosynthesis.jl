#FIXME: confusion between PFD vs. PPFD
@system SunlitWeather(Weather) begin
    radiation ~ ::Radiation(override)
    photosynthetic_photon_flux_density(x=radiation.irradiance_Q_sunlit): PPFD ~ track(u"μmol/m^2/s" #= Quanta =#)
end

@system ShadedWeather(Weather) begin
    radiation ~ ::Radiation(override)
    photosynthetic_photon_flux_density(x=radiation.irradiance_Q_shaded): PPFD ~ track(u"μmol/m^2/s" #= Quanta =#)
end

#TODO rename to CarbonAssimilation or so? could be consistently named as CarbonPartition, CarbonAllocation...
@system Photosynthesis begin
    weather ~ hold
    soil ~ hold

    leaf_area_index: LAI ~ hold
    planting_density: PD ~ hold

    water_supply ~ hold

    CO2_weight ~ hold
    CH2O_weight ~ hold
    H2O_weight ~ hold

    #FIXME remove dep to Photosynthesis
    radiation(context, weather, LAI) => Radiation(; context=context, sun=weather.sun, photosynthesis=self) ~ ::Radiation

    sunlit_weather(context, weather, radiation) => SunlitWeather(; context=context, weather=weather, radiation=radiation) ~ ::SunlitWeather
    shaded_weather(context, weather, radiation) => ShadedWeather(; context=context, weather=weather, radiation=radiation) ~ ::ShadedWeather

    # Calculating transpiration and photosynthesis with stomatal controlled by leaf water potential LeafWP Y
    #TODO: use leaf_nitrogen_content, leaf_width, ET_supply
    sunlit_gasexchange(context, soil, sunlit_weather) => GasExchange(; context=context, soil=soil, name="Sunlit", weather=sunlit_weather) ~ ::GasExchange
    shaded_gasexchange(context, soil, shaded_weather) => GasExchange(; context=context, soil=soil, name="Shaded", weather=shaded_weather) ~ ::GasExchange

    leaf_width => begin
        # to be calculated when implemented for individal leaves
        #5.0 # for maize
        1.5 # for garlic
    end ~ preserve(u"cm", parameter)

    #TODO how do we get LeafWP and ET_supply?
    leaf_water_potential(x=soil.WP_leaf): LWP ~ track(u"MPa")

    evapotranspiration_supply(LAI, PD, ws=water_supply, ww=H2O_weight) => begin
        #TODO common handling logic for zero LAI
        #FIXME check unit conversion (w.r.t water_supply)
        # ? * (1/m^2) / (3600s/hour) / (g/umol) / (cm^2/m^2) = mol/m^2/s H2O
        # ? * (1/m^2) * (hour/3600s) * (umol/g) * (m^2/cm^2) = mol/m^2/s H2O
        # ?(g / hour) * (hour/3600s) * (umol/g) / cm^2
        s = ws * PD / 3600 / ww / LAI
        #FIXME isinf necessary?
        isinf(s) ? 0. : s
    end ~ track(u"mol/m^2/s" #= H2O =#)

    sunlit_leaf_area_index(x=radiation.sunlit_leaf_area_index): LAI_sunlit ~ track(u"cm^2/m^2")
    shaded_leaf_area_index(x=radiation.shaded_leaf_area_index): LAI_shaded  ~ track(u"cm^2/m^2")

    weighted(LAI_sunlit, LAI_shaded; array) => begin
        v = [LAI_sunlit LAI_shaded] * array
        #FIXME better way to handling 1-element array value?
        v[1]
    end ~ call

    sunlit_irradiance(x=radiation.irradiance_Q_sunlit) ~ track(u"μmol/m^2/s" #= Quanta =#)
    shaded_irradiance(x=radiation.irradiance_Q_shaded) ~ track(u"μmol/m^2/s" #= Quanta =#)

    gross_array(a=sunlit_gasexchange.A_gross, b=shaded_gasexchange.A_gross) => [a, b] ~ track::Vector{Float64}(u"μmol/m^2/s")
    net_array(a=sunlit_gasexchange.A_net, b=shaded_gasexchange.A_net) => [a, b] ~ track::Vector{Float64}(u"μmol/m^2/s")
    evapotranspiration_array(a=sunlit_gasexchange.ET, b=shaded_gasexchange.ET) => [a, b] ~ track::Vector{Float64}(u"μmol/m^2/s")
    #temperature_array(a=sunlit.T_leaf, b=shaded.T_leaf) => [a, b] ~ track::Vector{Float64}(u"°C")
    conductance_array(a=sunlit_gasexchange.gs, b=shaded_gasexchange.gs) => [a, b] ~ track::Vector{Float64}(u"μmol/m^2/s")

    gross_CO2_umol_per_m2_s(weighted, gross_array): A_gross => weighted(array=gross_array) ~ track(u"μmol/m^2/s" #= CO2 =#)

    # plantsPerMeterSquare units are umol CO2 m-2 ground s-1
    # in the following we convert to g C plant-1 per hour
    # photosynthesis_gross is umol CO2 m-2 leaf s-1

    net_CO2_umol_per_m2_s(weighted, net_array): A_net => begin
        # grams CO2 per plant per hour
        weighted(array=net_array)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    transpiration_H2O_mol_per_m2_s(weighted, evapotranspiration_array): ET => begin
        #TODO need to save this?
        # when outputting the previous step transpiration is compared to the current step's water uptake
        #self.transpiration_old = self.transpiration
        #FIXME need to check if LAIs are negative?
        #transpiration = sunlit_gasexchange.ET * max(0, sunlit_LAI) + shaded_gasexchange.ET * max(0, shaded_LAI)
        weighted(array=evapotranspiration_array)
    end ~ track(u"μmol/m^2/s" #= H2O =#)

    # final values
    #TODO check final units
    assimilation(A_gross, PD, w=CO2_weight) => begin
        # grams CO2 per plant per hour
        A_gross / PD * w
    end ~ capture(u"g")

    gross_assimilation(A_gross, PD, w=CH2O_weight) => begin
        # grams carbo per plant per hour
        #FIXME check unit conversion between C/CO2 to CH2O
        A_gross / PD * w
    end ~ capture(u"g")

    net_assimilation(A_net, PD, w=CH2O_weight) => begin
        # grams carbo per plant per hour
        #FIXME check unit conversion between C/CO2 to CH2O
        A_net / PD * w
    end ~ capture(u"g")

    transpiration(ET, PD, w=H2O_weight) => begin
        # Units of Transpiration from sunlit->ET are mol m-2 (leaf area) s-1
        # Calculation of transpiration from ET involves the conversion to gr per plant per hour
        ET / PD * w
    end ~ capture(u"g")

    #FIXME: no sense to weight two temperature values here?
    #temperature(weighted, temperature_array) => weighted(array=temperature_array) ~ track(u"°C")

    vapor_pressure_deficit(VPD=sunlit_gasexchange.VPD) => begin
        #HACK only use sunlit leaves?
        max(0.0u"kPa", VPD)
    end ~ track(u"kPa")

    conductance(LAI_sunlit, LAI_shaded, weighted, conductance_array, LAI) => begin
        #HACK ensure 0 when one of either LAI is 0, i.e., night
        if iszero(LAI_sunlit) || iszero(LAI_shaded)
            0.
        else
            # average stomatal conductance Yang
            weighted(array=conductance_array) / LAI
            #c = max(0, c)
            #isinf(c) ? 0. : c
        end
    end ~ track(u"μmol/m^2/s")
end
