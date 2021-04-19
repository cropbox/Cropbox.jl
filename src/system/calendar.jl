using TimeZones: TimeZones, ZonedDateTime, @tz_str
import Dates

@system Calendar begin
    init ~ preserve::ZonedDateTime(extern, parameter)
    last => nothing ~ preserve::ZonedDateTime(extern, parameter, optional)
    time(t0=init, t=nounit(context.clock.time, u"s")) => t0 + (t |> round |> Dates.Second) ~ track::ZonedDateTime
    step(context.clock.step) ~ preserve(u"hr")
    stop(time, last) => begin
        isnothing(last) ? false : (time >= last)
    end ~ flag
    count(init, last, step) => begin
        if isnothing(last)
            nothing
        else
            # number of update!() required to reach `last` time
            (last - init) / step
        end
    end ~ preserve::Int(round, optional)
end

export Calendar
