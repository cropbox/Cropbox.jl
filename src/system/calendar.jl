using TimeZones: TimeZones, ZonedDateTime, @tz_str
import Dates

@system Calendar begin
    init => ZonedDateTime(2017, 7, 16, tz"America/Los_Angeles") ~ preserve::ZonedDateTime(extern, parameter)
    last => nothing ~ preserve::ZonedDateTime(extern, parameter, optional)
    time(t0=init, t=nounit(context.clock.time, u"s")) => t0 + (t |> round |> Dates.Second) ~ track::ZonedDateTime
    stop(time, last) => begin
        isnothing(last) ? false : (time >= last)
    end ~ flag
    count(init, last, Δt=nounit(context.clock.step, u"s")) => begin
        if isnothing(last)
            nothing
        else
            # number of update!() required to reach `last` time
            Dates.value(ceil(last - init, Dates.Second)) / Δt
        end
    end ~ preserve::Int(optional)
end

export Calendar
