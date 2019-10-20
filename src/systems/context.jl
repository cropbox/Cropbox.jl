@system Context begin
    context ~ ::Nothing
    config ~ ::Config(override)
	queue ~ ::Queue
    clock(config) ~ ::Clock
end
