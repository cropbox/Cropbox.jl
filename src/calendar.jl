using TimeZones
using Dates

@system Calendar begin
    init: t0 => default(ZonedDateTime) ~ preserve(parameter)
    time(t0, tick="context.clock.tick"): t => t0 + (tick |> u"s" |> ustrip |> Second) ~ track::ZonedDateTime
end

default(::Type{ZonedDateTime}) = ZonedDateTime(2017, 7, 16, tz"America/Los_Angeles")

export Calendar
