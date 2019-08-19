@system Clock begin
    self => self ~ ::System
    context ~ ::System(override)
    unit => NoUnits ~ preserve(parameter)
    init => 0 ~ preserve(unit="unit", parameter)
    step => 1 ~ preserve(unit="unit", parameter)
    tick => nothing ~ advance(init="init", step="step", unit="unit")
    tock => nothing ~ advance
end bare

advance!(c::Clock) = (advance!(c.tick); reset!(c.tock))
recite!(c::Clock) = advance!(c.tock)
