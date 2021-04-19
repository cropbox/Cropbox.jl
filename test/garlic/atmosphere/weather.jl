@system Weather begin
    calendar(context) ~ ::Calendar(override)
    vp(context): vapor_pressure ~ ::VaporPressure

    s: store ~ provide(init=calendar.time, parameter)

    PFD: photon_flux_density ~ drive(from=s, by=:SolRad, u"μmol/m^2/s") #Quanta
    #PFD => 1500 ~ track # umol m-2 s-1

    CO2 => 400 ~ preserve(u"μmol/mol", parameter)

    RH: relative_humidity ~ drive(from=s, by=:RH, u"percent")
    #RH => 0.6 ~ track # 0~1

    T_air: air_temperature ~ drive(from=s, by=:Tair, u"°C")
    #T_air => 25 ~ track # C

    Tk_air(T_air): absolute_air_temperature ~ track(u"K")

    wind: wind_speed ~ drive(from=s, by=:Wind, u"m/s")
    #wind => 2.0 ~ track # meters s-1

    #TODO: make P_air parameter?
    P_air: air_pressure => 100 ~ track(u"kPa")

    VPD(T_air, RH, D=vp.D): vapor_pressure_deficit => D(T_air, RH) ~ track(u"kPa")
    VPD_Δ(T_air, Δ=vp.Δ): vapor_pressure_saturation_slope_delta => Δ(T_air) ~ track(u"kPa/K")
    VPD_s(T_air, P_air, s=vp.s): vapor_pressure_saturation_slope => s(T_air, P_air) ~ track(u"K^-1")
end

#TODO: make @stub macro to automate this
@system WeatherStub begin
    weather ~ hold

    vp(x=weather.vp) => x ~ ::VaporPressure

    PFD(weather.PFD): photon_flux_density ~ track(u"μmol/m^2/s" #= Quanta =#)
    CO2(weather.CO2) ~ track(u"μmol/mol")
    RH(weather.RH): relative_humidity ~ track(u"percent")
    T_air(weather.T_air): air_temperature ~ track(u"°C")
    Tk_air(weather.Tk_air): absolute_air_temperature ~ track(u"K")
    wind(weather.wind): wind_speed ~ track(u"m/s")
    P_air(weather.P_air): air_pressure ~ track(u"kPa")

    VPD(weather.VPD): vapor_pressure_deficit ~ track(u"kPa")
    VPD_Δ(weather.VPD_Δ): vapor_pressure_saturation_slope_delta ~ track(u"kPa/K")
    VPD_s(weather.VPD_s): vapor_pressure_saturation_slope ~ track(u"K^-1")
end
