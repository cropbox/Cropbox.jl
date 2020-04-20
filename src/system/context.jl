@system Context begin
    context ~ ::Nothing
    config ~ ::Cropbox.Config(override)
    clock(config) ~ ::Cropbox.Clock
end
