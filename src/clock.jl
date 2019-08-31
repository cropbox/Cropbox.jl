@system Clock begin
    self => self ~ ::System
    context ~ ::System(override)
    unit => nothing ~ preserve(static, parameter)
    init => 0 ~ preserve(unit="unit", static, parameter)
    step => 1 ~ preserve(unit="unit", static, parameter)
    tick => nothing ~ advance(init="init", step="step", unit="unit")
end

advance!(c::Clock) = advance!(c.tick)
