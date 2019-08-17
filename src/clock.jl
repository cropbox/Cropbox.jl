@system Clock begin
    self => self ~ ::System
    context ~ ::System(override)
    tick => nothing ~ advance
    tock => nothing ~ advance
    unit => NoUnits ~ preserve::Unitful.Units # parameter
    start => 0 ~ preserve(unit="unit") # parameter
    interval: i => 1 ~ track(time="tick", unit="unit") # parameter
    time(i) => i ~ accumulate::Int(init="start", time="tick", unit="unit")
    #start_datetime ~ parameter
    #datetime
end bare

advance!(c::Clock) = (advance!(c.tick); reset!(c.tock))
recite!(c::Clock) = advance!(c.tock)
