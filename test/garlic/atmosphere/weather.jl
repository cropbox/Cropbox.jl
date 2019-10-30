using TimeZones
using DataFrames
using CSV

#TODO: use improved @drive
#TODO: implement @unit
@system Weather begin
    calendar(context) ~ ::Calendar(override)

    vapor_pressure(context): vp ~ ::VaporPressure

    filename => "" ~ preserve::String(parameter)
    timezone => tz"UTC" ~ preserve::TimeZone(parameter)
    index => :timestamp ~ preserve::Symbol(parameter)

    dataframe(filename, index, timezone): df => begin
        df = CSV.read(filename)
        df[!, index] = map(eachrow(df)) do r
            datetime_from_julian_day_WEA(r.year, r.jday, r.time, timezone)
        end
        df
    end ~ preserve::DataFrame
    key(t=calendar.time) => t ~ track::ZonedDateTime
    store(df, index, key): s => begin
        df[df[!, index] .== key, :][1, :]
    end ~ track::DataFrameRow{DataFrame,DataFrames.Index}
    #Dict(:SolRad => 1500, :CO2 => 400, :RH => 0.6, :T_air => 25, :wind => 2.0, :P_air => 100)

    photon_flux_density(s): PFD ~ drive(key=:SolRad, u"μmol/m^2/s") #Quanta
    #PFD => 1500 ~ track # umol m-2 s-1

    #TODO: make CO2 parameter?
    CO2 => 400 ~ track(u"μmol/mol")

    #relative_humidity(s): RH ~ drive(key="RH", u"percent")
    relative_humidity(s): RH => s[:RH] ~ track(u"percent")
    #RH => 0.6 ~ track # 0~1

    air_temperature(s): T_air ~ drive(key=:Tair, u"°C")
    #T_air => 25 ~ track # C

    absolute_air_temperature(T_air): Tk_air ~ track(u"K")

    wind_speed(s): wind ~ drive(key=:Wind, u"m/s")
    #wind => 2.0 ~ track # meters s-1

    #TODO: make P_air parameter?
    air_pressure: P_air => 100 ~ track(u"kPa")

    vapor_pressure_deficit(T_air, RH, D=vp.D): VPD => D(T_air, RH) ~ track(u"kPa")
    vapor_pressure_saturation_slope(T_air, P_air, s=vp.s): VPD_slope => s(T_air, P_air) ~ track(u"K^-1")
end

# import Base: show
# show(io::IO, w::Weather) = print(io, "$(w.PFD)\n$(w.CO2)\n$(w.RH)\n$(w.T_air)\n$(w.wind)\n$(w.P_air)")

# o = (
#     :Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
#     :Weather => (:filename => "test/garlic/data/2007.wea"),
# )
#w = instance(Weather; config=o)
