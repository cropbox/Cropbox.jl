using TimeZones
import Dates

@system Estimator(DataFrameStore) begin
    year ~ preserve(parameter)::Int

    Ds: start_date_offset => 0 ~ preserve(optional)::Int

    # 150 days after new year (around end of May)
    De: end_date_offset => 150 ~ preserve::Int
    
    tz: timezone => tz"UTC" ~ preserve(parameter)::TimeZone

    t0: start_date(year, tz, Ds) => begin
        if isnothing(Ds)
            ZonedDateTime(year-1, 10, 1, tz)
        else
            ZonedDateTime(year, 1, 1, tz) + Dates.Day(Ds)
        end
    end ~ preserve::ZonedDateTime

    t1: end_date(year, tz, De) => begin
        ZonedDateTime(year, 1, 1, tz) + Dates.Day(De)
    end ~ preserve::ZonedDateTime

    calendar(context, init=t0) ~ ::Calendar
    t(calendar.time) ~ track::ZonedDateTime
    stop(t, t1) => t >= t1 ~ flag

    index(t) ~ track::ZonedDateTime
    timestamp(timezone; r::DataFrameRow) => begin
        #r.timestamp
    end ~ call::ZonedDateTime

    T(s): temperature => s[:tavg] ~ track(u"°C")
end