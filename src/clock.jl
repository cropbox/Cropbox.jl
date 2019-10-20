@system Clock begin
    context ~ ::Nothing
    config ~ ::Cropbox.Config(override)
    init => 0 ~ preserve(u"hr", parameter)
    step => 1 ~ preserve(u"hr", parameter)
    tick => nothing ~ advance(init=init, step=step, unit=u"hr")
end
