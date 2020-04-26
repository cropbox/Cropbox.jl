@system TemperatureDependence begin
    T: leaf_temperature ~ hold
    Tk(T): absolute_leaf_temperature ~ track(u"K")

    Tb: base_temperature => 25 ~ preserve(u"°C", parameter)
    Tbk(Tb): absolute_base_temperature ~ preserve(u"K")

    kT(T, Tk, Tb, Tbk; Ea(u"kJ/mol")): arrhenius_equation => begin
        exp(Ea * (T - Tb) / (u"R" * Tk * Tbk))
    end ~ call

    kTpeak(Tk, Tbk, kT; Ea(u"kJ/mol"), S(u"J/mol/K"), H(u"kJ/mol")): peaked_function => begin
        R = u"R"
        kT(Ea) * (1 + exp((S*Tbk - H) / (R*Tbk))) / (1 + exp((S*Tk - H) / (R*Tk)))
    end ~ call

    Q10 => 2 ~ preserve(parameter)
    kTQ10(T, Tb, Q10): q10_rate => begin
        Q10^((T - Tb) / 10u"K")
    end ~ track
end

@system NitrogenDependence begin
    N: leaf_nitrogen_content ~ hold

    s => 2.9 ~ preserve(u"m^2/g", parameter)
    N0 => 0.25 ~ preserve(u"g/m^2", parameter)

    kN(N, s, N0): nitrogen_limited_rate => begin
        2 / (1 + exp(-s * (max(N0, N) - N0))) - 1
    end ~ track
end

@system CBase(TemperatureDependence, NitrogenDependence) begin
    Ci: intercellular_co2 ~ hold
    I2: effective_irradiance ~ hold
end
