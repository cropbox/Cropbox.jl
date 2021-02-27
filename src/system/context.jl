@system Context begin
    context ~ ::Nothing
    config ~ ::Config(override)
    clock(config) ~ ::Clock
end

export Context
