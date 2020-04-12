@system TemperatureDependence begin
    T: leaf_temperature ~ hold
    Tk(T): absolute_leaf_temperature ~ track(u"K")

    Tb: base_temperature => 25 ~ preserve(u"°C", parameter)
    Tbk(Tb): absolute_base_temperature ~ preserve(u"K")

    T_dep(T, Tk, Tb, Tbk; Ea(u"kJ/mol")): temperature_dependence_rate => begin
        exp(Ea * (T - Tb) / (Tbk * u"R" * Tk))
    end ~ call
end

@system NitrogenDependence begin
    N: nitrogen ~ hold

    s => 2.9 ~ preserve(u"m^2/g", parameter)
    N0 => 0.25 ~ preserve(u"g/m^2", parameter)

    N_dep(N, s, N0): nitrogen_limited_rate => begin
        2 / (1 + exp(-s * (max(N0, N) - N0))) - 1
    end ~ track
end

@system CBase(TemperatureDependence, NitrogenDependence) begin
    Ci: intercellular_co2 ~ hold
    I2: effective_irradiance ~ hold
end
