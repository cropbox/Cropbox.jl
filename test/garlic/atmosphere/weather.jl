using TimeZones
using DataFrames
using CSV

#TODO: use improved @drive
#TODO: implement @unit
@system Weather(DataFrameStore) begin
    calendar(context) ~ ::Calendar(override)
    vp(context): vapor_pressure ~ ::VaporPressure

    tz: timezone => tz"UTC" ~ preserve::TimeZone(parameter)

    i(calendar.time): index ~ track::ZonedDateTime
    t(tz; r::DataFrameRow): timestamp => begin
        datetime_from_julian_day_WEA(r.year, r.jday, r.time, tz)
    end ~ call::ZonedDateTime

    PFD(s): photon_flux_density ~ drive(key=:SolRad, u"μmol/m^2/s") #Quanta
    #PFD => 1500 ~ track # umol m-2 s-1

    #TODO: make CO2 parameter?
    CO2 => 400 ~ track(u"μmol/mol")

    #RH(s): relative_humidity ~ drive(key="RH", u"percent")
    RH(s): relative_humidity => s[:RH] ~ track(u"percent")
    #RH => 0.6 ~ track # 0~1

    T_air(s): air_temperature ~ drive(key=:Tair, u"°C")
    #T_air => 25 ~ track # C

    Tk_air(T_air): absolute_air_temperature ~ track(u"K")

    wind(s): wind_speed ~ drive(key=:Wind, u"m/s")
    #wind => 2.0 ~ track # meters s-1

    #TODO: make P_air parameter?
    P_air: air_pressure => 100 ~ track(u"kPa")

    VPD(T_air, RH, D=vp.D): vapor_pressure_deficit => D(T_air, RH) ~ track(u"kPa")
    VPD_Δ(T_air, Δ=vp.Δ): vapor_pressure_saturation_slope_delta => Δ(T_air) ~ track(u"kPa/K")
    VPD_s(T_air, P_air, s=vp.s): vapor_pressure_saturation_slope => s(T_air, P_air) ~ track(u"K^-1")
end

# import Base: show
# show(io::IO, w::Weather) = print(io, "$(w.PFD)\n$(w.CO2)\n$(w.RH)\n$(w.T_air)\n$(w.wind)\n$(w.P_air)")

# o = (
#     :Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
#     :Weather => (:filename => "test/garlic/data/2007.wea"),
# )
#w = instance(Weather; config=o)
