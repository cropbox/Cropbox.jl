using TimeZones
import Dates

@system Calendar begin
    context ~ ::Nothing
    config ~ ::Cropbox.Config(override)
    clock ~ ::Cropbox.Clock(override)
    init => ZonedDateTime(0, 1, 1, tz"UTC") ~ preserve::ZonedDateTime(extern, parameter)
    last => nothing ~ preserve::ZonedDateTime(extern, parameter, optional)
    time(t0=init, t=clock.tick) => begin
        #HACK: round needed for accounting accumulation error with small time step
        t0 + (Cropbox.deunitfy(t, u"s") |> round |> Dates.Second)
    end ~ track::ZonedDateTime
    stop(time, last) => begin
        isnothing(last) ? false : (time >= last)
    end ~ track::Bool
    count(init, last, Δt=clock.step) => begin
        if isnothing(last)
            nothing
        else
            # number of update!() required to reach `last` time
            Dates.value(ceil(last - init, Dates.Second)) / Cropbox.deunitfy(Δt, u"s") - 1
        end
    end ~ preserve::Int(optional)
end

export Calendar
