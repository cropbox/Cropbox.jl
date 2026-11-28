using TimeZones: TimeZones, ZonedDateTime, @tz_str
export ZonedDateTime, @tz_str
using Dates: Dates, Date
export Dates, Date

calendarduration(t) = begin
    ms = deunitfy(t, u"ms")
    isinteger(ms) || throw(ArgumentError("Calendar requires a whole number of milliseconds, got $t"))
    Dates.Millisecond(ms)
end

@system Calendar begin
    init ~ preserve::datetime(extern, parameter)
    last => nothing ~ preserve::datetime(extern, parameter, optional)
    time(t0=init, t=context.clock.time) => t0 + Cropbox.calendarduration(t) ~ track::datetime
    date(time) => Cropbox.Dates.Date(time) ~ track::date
    step(dt=context.clock.step) => Cropbox.calendarduration(dt) ~ preserve::rational(u"hr")
    stop(time, last) => begin
        isnothing(last) ? false : (time >= last)
    end ~ flag
    count(time, last, step) => begin
        if isnothing(last)
            nothing
        elseif time >= last
            0
        elseif step <= zero(step)
            throw(ArgumentError("Calendar needs a positive Clock.step to reach a future end date, got $step"))
        else
            (last - time) / step
        end
    end ~ preserve::int(round, optional)
end

export Calendar
