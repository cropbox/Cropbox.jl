@system VaporPressure begin
    # Campbell and Norman (1998), p 41 Saturation vapor pressure in kPa
    a => 0.611 ~ preserve(u"kPa", parameter)
    b => 17.502 ~ preserve(parameter) # C
    c => 240.97 ~ preserve(parameter) # C

    saturation(a, b, c, T): es => (@nounit T; a*exp((b*T)/(c+T))) ~ call(u"kPa")
    ambient(es, T, RH): ea => es(T) * RH ~ call(u"kPa")
    deficit(es, T, RH): D => es(T) * (1 - RH) ~ call(u"kPa")
    relative_humidity(es, T, VPD): rh => 1 - VPD / es(T) ~ call(u"NoUnits")

    # slope of the sat vapor pressure curve: first order derivative of Es with respect to T
    saturation_slope_delta(es, b, c, T): Delta => (@nounit T; es(T) * (b*c)/(c+T)^2 / u"K") ~ call(u"kPa/K")
    saturation_slope(Delta, T, P): s => Delta(T) / P ~ call(u"K^-1")
end
