abstract type Clock <: System end
timeunit(::Type{<:Clock}) = u"hr"
@system Clock{timeunit = timeunit(Clock)} begin
    context ~ ::Nothing
    config ~ ::Config(override)
    init => 0 ~ preserve(unit=timeunit, parameter)
    step => 1 ~ preserve(unit=timeunit, parameter)
    tick => nothing ~ advance(init=init, step=step, unit=timeunit)
end

timeunit(c::C) where {C<:Clock} = timeunit(C)

export Clock
