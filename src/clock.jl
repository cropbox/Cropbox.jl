@system Clock begin
    self => self ~ ::System
    context => nothing ~ ::Nothing
    config ~ ::Config(override, expose)
    unit => nothing ~ preserve(parameter)
    init => 0 ~ preserve(unit=unit, parameter)
    step => 1 ~ preserve(unit=unit, parameter)
    tick => nothing ~ advance(init=init, step=step, unit=unit)
end

advance!(c::Clock) = advance!(c.tick)
