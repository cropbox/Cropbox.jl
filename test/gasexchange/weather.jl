using DataFrames

@system Weather(DataFrameStore) begin
    # calendar(context) ~ ::Calendar(override)
    vp(context): vapor_pressure ~ ::VaporPressure

    PFD(s): photon_flux_density ~ drive(key=:SolRad, u"μmol/m^2/s") #Quanta
    CO2(s) => s[:CO2] ~ track(u"μmol/mol")
    RH(s): relative_humidity => s[:RH] ~ track(u"percent")
    T_air(s): air_temperature => s[:Tair] ~ track(u"°C")
    Tk_air(T_air): absolute_air_temperature ~ track(u"K")
    wind(s): wind_speed => s[:Wind] ~ track(u"m/s")

    #TODO: make P_air parameter?
    P_air: air_pressure => 100 ~ track(u"kPa")

    VPD(T_air, RH, D=vp.D): vapor_pressure_deficit => D(T_air, RH) ~ track(u"kPa")
    VPD_Δ(T_air, Δ=vp.Δ): vapor_pressure_saturation_slope_delta => Δ(T_air) ~ track(u"kPa/K")
    VPD_s(T_air, P_air, s=vp.s): vapor_pressure_saturation_slope => s(T_air, P_air) ~ track(u"K^-1")
end

#TODO: make @stub macro to automate this
@system WeatherStub begin
    weather ~ hold

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
