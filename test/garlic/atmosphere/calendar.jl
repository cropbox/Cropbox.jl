using Dates
using TimeZones

const JULIAN_EPOCH_USDA = 2415078.5 # 1990-03-01
const JULIAN_EPOCH_UNIX = 2440587.5 # 1970-01-01

datetime_from_julian_day_WEA(year, jday, time::Time, tz::TimeZone, occurrence) =
    zoned_datetime(Date(year) + (Day(jday) - Day(1)) + time, tz, occurrence)
datetime_from_julian_day_WEA(year, jday, tz::TimeZone) = datetime_from_julian_day_WEA(year, jday, "00:00", tz)
#HACK: handle different API for Fixed/VariableTimeZone
zoned_datetime(dt::DateTime, tz::TimeZone, occurrence=1) = ZonedDateTime(dt, tz)
zoned_datetime(dt::DateTime, tz::VariableTimeZone, occurrence=1) = ZonedDateTime(dt, tz, occurrence)

#julian_day_from_datetime(clock::Dates.AbstractDateTime) = dayofyear(clock)

#round_datetime(clock::Dates.AbstractDateTime) = round(clock, Minute)

datetime_from_julian_day_2DSOIL(jday, jhour=0) = begin
    d = (jday + jhour) + (JULIAN_EPOCH_USDA - JULIAN_EPOCH_UNIX)
    #HACK prevent degenerate timestamps due to precision loss
    t = ZonedDateTime(1970, 1, 1, tz"UTC") + Day(d)
    round(t, Minute)
end

julian_day_from_datetime_2DSOIL(clock::ZonedDateTime; hourly=false) = begin
    s = clock - ZonedDateTime(1970, 1, 1, tz"UTC") |> Second
    j = s - (JULIAN_EPOCH_USDA - JULIAN_EPOCH_UNIX)
    #FIXME: type instability
    hourly ? j : Int(round(j))
end

julian_hour_from_datetime_2DSOIL(clock::ZonedDateTime) =
    julian_day_from_datetime_2DSOIL(clock; hourly=true) - julian_day_from_datetime_2DSOIL(clock; hourly=false)

using CSV
using DataFrames: DataFrames, DataFrame

loadwea(filename, timezone; indexkey=:index) = begin
    df = CSV.File(filename) |> DataFrame
    df[!, indexkey] = map(r -> begin
        occurrence = 1
        i = DataFrames.row(r)
        if i > 1
            r0 = parent(r)[i-1, :]
            r0.time == r.time && (occurrence = 2)
        end
        datetime_from_julian_day_WEA(r.year, r.jday, r.time, timezone, occurrence)
    end, eachrow(df))
    df
end
