@system Context begin
    context ~ ::Nothing
    config ~ ::Config(override)
    clock(config) ~ ::Clock
end

#TODO: remove once Context and Clock get merged
@system DailyContext{Clock => DailyClock}(Context) <: Context

timeunit(c::Context) = timeunit(c.clock)

#HACK: explicitly set up timeunit for default Context
#TODO: merge Context and Clock to remove boilerplates
timeunit(::Type{Context}) = timeunit(Clock)
timeunit(::Type{typefor(Context)}) = timeunit(Context)

#HACK: fallback when timeunit() not available for custom Context
timeunit(C::Type{<:Context}) = only(filter!(v -> v.name == :clock, geninfos(C))).type |> scopeof(C).eval |> timeunit

export Context
