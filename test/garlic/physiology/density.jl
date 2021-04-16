@system Density begin
    weather ~ hold

    PD0: initial_planting_density => 55 ~ preserve(u"m^-2", parameter)

    CDSF: cold_damage_shape_factor => 0.9 ~ preserve(u"K^-1", parameter)
    CDCT: cold_damage_critical_temperature => -15 ~ preserve(u"°C", parameter)

    enable_cold_damage => true ~ flag(parameter)

    "mortality due to cold damage (2019-08-09: KHM, KDY)"
    CDM(s=CDSF, Tc=CDCT, T=weather.T_air): cold_damage_mortality => begin
        x = exp(-s * (T - Tc))
        x / (1 + x)
    end ~ track(u"d^-1", when=enable_cold_damage)

    CDS(CDS, CDM): cold_damage_survival_rate => (CDS * -CDM) ~ accumulate(init=1, min=0)

    PD(PD0, CDS): planting_density => (PD0 * CDS) ~ track(u"m^-2")
end
