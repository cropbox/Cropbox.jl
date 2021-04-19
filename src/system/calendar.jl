using TimeZones: TimeZones, ZonedDateTime, @tz_str
import Dates

@system Calendar begin
    init ~ preserve::datetime(extern, parameter)
    last => nothing ~ preserve::datetime(extern, parameter, optional)
    time(t0=init, t=context.clock.time) => t0 + convert(Dates.Second, t) ~ track::datetime
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
