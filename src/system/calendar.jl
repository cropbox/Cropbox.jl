using TimeZones
import Dates

@system Calendar begin
    init => ZonedDateTime(2017, 7, 16, tz"America/Los_Angeles") ~ preserve::ZonedDateTime(extern, parameter)
    time(t0=init, t=context.clock.tick) => t0 + (Cropbox.deunitfy(t, u"s") |> Dates.Second) ~ track::ZonedDateTime
end

export Calendar
