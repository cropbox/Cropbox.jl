@system Context begin
    context ~ ::Nothing
    config ~ ::Cropbox.Config(override)
	queue ~ ::Cropbox.Queue
    clock(config) ~ ::Cropbox.Clock
end
