using TimeZones: TimeZones, ZonedDateTime, @tz_str
import Dates

@system Calendar begin
    init => ZonedDateTime(2017, 7, 16, tz"America/Los_Angeles") ~ preserve::ZonedDateTime(extern, parameter)
    last => nothing ~ preserve::ZonedDateTime(extern, parameter, optional)
    time(t0=init, t=nounit(context.clock.time, u"s")) => t0 + (t |> round |> Dates.Second) ~ track::ZonedDateTime
    step(Δt=nounit(context.clock.step, u"s")) => Dates.Second(Δt) ~ preserve::Dates.Second
    stop(time, last) => begin
        isnothing(last) ? false : (time >= last)
    end ~ flag
    count(init, last, step) => begin
        if isnothing(last)
            nothing
        else
            # number of update!() required to reach `last` time
            ceil(last - init, Dates.Second) / step
        end
    end ~ preserve::Int(optional)
end

export Calendar
