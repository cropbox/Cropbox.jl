using TimeZones
import Dates

@system Calendar begin
    t0: init => ZonedDateTime(2017, 7, 16, tz"America/Los_Angeles") ~ preserve::ZonedDateTime(extern, parameter)
    t(t0, Δt=context.clock.tick): time => t0 + (Cropbox.deunitfy(Δt, u"s") |> Dates.Second) ~ track::ZonedDateTime
end

export Calendar
