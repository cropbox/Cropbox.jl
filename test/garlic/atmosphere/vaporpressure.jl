@system VaporPressure begin
    # Campbell and Norman (1998), p 41 Saturation vapor pressure in kPa
    a => 0.611 ~ preserve(u"kPa", parameter)
    b => 17.502 ~ preserve(parameter)
    c => 240.97 ~ preserve(parameter) # °C

    saturation(a, b, c; T(u"°C")): es => (t = ustrip(T); a*exp((b*t)/(c+t))) ~ call(u"kPa")
    ambient(es; T(u"°C"), RH(u"percent")): ea => es(T) * RH ~ call(u"kPa")
    deficit(es; T(u"°C"), RH(u"percent")): D => es(T) * (1 - RH) ~ call(u"kPa")
    relative_humidity(es; T(u"°C"), VPD(u"kPa")): rh => 1 - VPD / es(T) ~ call(u"NoUnits")

    # slope of the sat vapor pressure curve: first order derivative of Es with respect to T
    saturation_slope_delta(es, b, c; T(u"°C")): Delta => (e = es(T); t = ustrip(T); e*(b*c)/(c+t)^2 / u"K") ~ call(u"kPa/K")
    saturation_slope(Delta; T(u"°C"), P(u"kPa")): s => Delta(T) / P ~ call(u"K^-1")
end
