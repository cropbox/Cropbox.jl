@system Clock begin
    self => self ~ ::System
    context ~ ::System(override)
    tick => nothing ~ advance
    tock => nothing ~ advance
    #unit
    start => 0 ~ track(time="tick") # parameter
    interval: i => 1 ~ track(time="tick") # parameter
    time(i) => i ~ accumulate::Int(init=0, time="tick")
    #start_datetime ~ parameter
    #datetime
end bare

advance!(c::Clock) = (advance!(c.tick); reset!(c.tock))
recite!(c::Clock) = advance!(c.tock)
