@system Weather begin
    vp(context): vapor_pressure ~ ::VaporPressure

    PFD: photon_flux_density ~ preserve(u"μmol/m^2/s", parameter) #Quanta
    CO2: carbon_dioxide ~ preserve(u"μmol/mol", parameter)
    RH: relative_humidity ~ preserve(u"percent", parameter)
    T_air: air_temperature ~ preserve(u"°C", parameter)
    Tk_air(T_air): absolute_air_temperature ~ track(u"K")
    wind: wind_speed ~ preserve(u"m/s", parameter)
    P_air: air_pressure => 100 ~ preserve(u"kPa", parameter)

    VPD(T_air, RH, D=vp.D): vapor_pressure_deficit => D(T_air, RH) ~ track(u"kPa")
    VPD_Δ(T_air, Δ=vp.Δ): vapor_pressure_saturation_slope_delta => Δ(T_air) ~ track(u"kPa/K")
    VPD_s(T_air, P_air, s=vp.s): vapor_pressure_saturation_slope => s(T_air, P_air) ~ track(u"K^-1")
end
