@system C3Base begin
    Ci: intercellular_co2 ~ hold
    I2: effective_irradiance ~ hold
    T: leaf_temperature ~ hold

    Tk(T): absolute_leaf_temperature ~ track(u"K")

    # Arrhenius equation
    Tb: base_temperature => 25 ~ preserve(u"°C", parameter)
    Tbk(Tb): absolute_base_temperature ~ preserve(u"K")
    T_dep(T, Tk, Tb, Tbk; Ea(u"kJ/mol")): temperature_dependence_rate => begin
        exp(Ea * (T - Tb) / (Tbk * u"R" * Tk))
    end ~ call
end

@system C3c(C3Base) begin
    # Michaelis constant of rubisco for CO2 of C3 plants, ubar, from Bernacchi et al. (2001)
    Kc25: rubisco_constant_for_co2_at_25 => 404.9 ~ preserve(u"μbar", parameter)
    # Activation energy for Kc, Bernacchi (2001)
    Eac: activation_energy_for_co2 => 79.43 ~ preserve(u"kJ/mol", parameter)
    Kc(T_dep, Kc25, Eac): rubisco_constant_for_co2 => begin
        Kc25 * T_dep(Eac)
    end ~ track(u"μbar")

    # Michaelis constant of rubisco for O2, mbar, from Bernacchi et al., (2001)
    Ko25: rubisco_constant_for_o2_at_25 => 278.4 ~ preserve(u"mbar", parameter)
    # Activation energy for Ko, Bernacchi (2001)
    Eao: activation_energy_for_o2 => 36.38 ~ preserve(u"kJ/mol", parameter)
    Ko(T_dep, Ko25, Eao): rubisco_constant_for_o2 => begin
        Ko25 * T_dep(Eao)
    end ~ track(u"mbar")

    # mesophyll O2 partial pressure
    Om: mesophyll_o2_partial_pressure => 210 ~ preserve(u"mbar", parameter)
    # effective M-M constant for Kc in the presence of O2
    Km(Kc, Om, Ko): rubisco_constant_for_co2_with_o2 => begin
        Kc * (1 + Om / Ko)
    end ~ track(u"μbar")

    Vcm25: maximum_carboxylation_rate_at_25 => 108.4 ~ preserve(u"μmol/m^2/s" #= CO2 =#, parameter)
    EaVc: activation_energy_for_carboxylation => 52.1573 ~ preserve(u"kJ/mol", parameter)
    Vcmax(T_dep, Vcm25, EaVc): maximum_carboxylation_rate => begin
        Vcm25 * T_dep(EaVc)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)
end

@system C3j(C3Base) begin
    Jm25: maximum_electron_transport_rate_at_25 => 169.0 ~ preserve(u"μmol/m^2/s" #= Electron =#, parameter)
    Eaj: activation_energy_for_electron_transport => 23.9976 ~ preserve(u"kJ/mol", parameter)
    Sj: electron_transport_temperature_response => 616.4 ~ preserve(u"J/mol/K", parameter)
    Hj: electron_transport_curvature => 200 ~ preserve(u"kJ/mol", parameter)
    Jmax(Tk, Tbk, T_dep, Jm25, Eaj, Sj, Hj): maximum_electron_transport_rate => begin
        R = u"R"
        Jm25 * begin
            T_dep(Eaj) *
            (1 + exp((Sj*Tbk - Hj) / (R*Tbk))) /
            (1 + exp((Sj*Tk  - Hj) / (R*Tk)))
        end
    end ~ track(u"μmol/m^2/s" #= Electron =#)

    # θ: sharpness of transition from light limitation to light saturation
    θ: light_transition_sharpness => 0.7 ~ preserve(parameter)
    J(I2, Jmax, θ): electron_transport_rate => begin
        a = θ
        b = -(I2+Jmax)
        c = I2*Jmax
        a*J^2 + b*J + c
    end ~ solve(lower=0, upper=Jmax, u"μmol/m^2/s")
end

@system C3p(C3Base) begin
    Tp25: triose_phosphate_limitation_at_25 => 16.03 ~ preserve(u"μmol/m^2/s" #= CO2 =#, parameter)
    EaTp: activation_energy_for_Tp => 47.10 ~ preserve(u"kJ/mol", parameter)
    Tp(T_dep, Tp25, EaTp): triose_phosphate_limitation => begin
        Tp25 * T_dep(EaTp)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)
end

@system C3r(C3Base) begin
    Rd25: dark_respiration_at_25 => 1.08 ~ preserve(u"μmol/m^2/s" #= O2 =#, parameter)
    Ear: activation_energy_for_respiration => 49.39 ~ preserve(u"kJ/mol", parameter)
    Rd(T_dep, Rd25, Ear): dark_respiration => begin
        Rd25 * T_dep(Ear)
    end ~ track(u"μmol/m^2/s")
    #Rm(Rd) => 0.5Rd ~ track(u"μmol/m^2/s")

    # CO2 compensation point in the absence of day respiration, value from Bernacchi (2001)
    Γ25: co2_compensation_point_at_25 => 42.75 ~ preserve(u"μbar", parameter)
    Eag: activation_energy_for_co2_compensation_point => 37.83 ~ preserve(u"kJ/mol", parameter)
    Γ(T_dep, Γ25, Eag): co2_compensation_point => begin
        Γ25 * T_dep(Eag)
    end ~ track(u"μbar")
end

@system C3Rate(C3c, C3j, C3p, C3r) begin
    Ac(Vcmax, Ci, Γ, Km, Rd): enzyme_limited_photosynthesis_rate => begin
        Vcmax * (Ci - Γ) / (Ci + Km) - Rd
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    # light and electron transport limited A mediated by J
    Aj(J, Ci, Γ, Rd): transport_limited_photosynthesis_rate => begin
        J * (Ci - Γ) / 4(Ci + 2Γ) - Rd
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    Ap(Tp): triose_phosphate_limited_photosynthesis_rate => begin
        3Tp
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    A_net(Ac, Aj, Ap): net_photosynthesis => begin
        min(Ac, Aj, Ap)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    A_gross(A_net, Rd): gross_photosynthesis => begin
        # gets negative when PFD = 0, Rd needs to be examined, 10/25/04, SK
        A_gross = A_net + Rd
        #max(A_gross, zero(A_gross))
    end ~ track(u"μmol/m^2/s" #= CO2 =#)
end

@system C3(C3Rate)
