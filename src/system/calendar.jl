using TimeZones
import Dates

@system Calendar begin
    init => ZonedDateTime(2017, 7, 16, tz"America/Los_Angeles") ~ preserve::ZonedDateTime(extern, parameter)
    last => nothing ~ preserve::ZonedDateTime(extern, parameter, optional)
    time(t0=init, t=context.clock.tick) => t0 + (Cropbox.deunitfy(t, u"s") |> Dates.Second) ~ track::ZonedDateTime
    stop(time, last) => begin
        isnothing(last) ? false : (time >= last)
    end ~ track::Bool
end

export Calendar
