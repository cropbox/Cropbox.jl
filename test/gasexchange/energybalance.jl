@system EnergyBalance(Weather) begin
    gv ~ hold
    gh ~ hold
    PPFD ~ hold

    ϵ: leaf_thermal_emissivity => 0.97 ~ preserve(parameter)
    σ: stefan_boltzmann_constant => u"σ" ~ preserve(u"W/m^2/K^4")
    λ: latent_heat_of_vaporization_at_25 => 44 ~ preserve(u"kJ/mol", parameter)
    Cp: specific_heat_of_air => 29.3 ~ preserve(u"J/mol/K", parameter)

    k: radiation_conversion_factor => (1 / 4.55) ~ preserve(u"J/μmol")
    PAR(PPFD, k): photosynthetically_active_radiation => (PPFD * k) ~ track(u"W/m^2")

    # NIR(PAR): near_infrared_radiation => begin
    #     #FIXME: maybe δ or similar ratio supposed to be applied here?
    #     # If total solar radiation unavailable, assume NIR the same energy as PAR waveband
    #     PAR
    # end ~ track(u"W/m^2")

    # solar radiation absorptivity of leaves: =~ 0.5
    #FIXME: is α different from (1 - δ) in Irradiance?
    α_s: absorption_coefficient => 0.5 ~ preserve(parameter)

    #R_sw(PAR, NIR, α_s, δ): shortwave_radiation_absorbed => begin
    R_sw(PAR, α_s): shortwave_radiation_absorbed => begin
        #FIXME: why δ needed here? α should already take care of scattering
        # shortwave radiation (PAR (=0.85) + NIR (=0.15))
        #α_s*((1-δ)*PAR + δ*NIR)
        α_s*PAR
    end ~ track(u"W/m^2")

    R_wall(ϵ, σ, Tk_air): thermal_radiation_absorbed_from_wall => 2ϵ*σ*Tk_air^4 ~ track(u"W/m^2")
    R_leaf(ϵ, σ, Tk): thermal_radiation_emitted_by_leaf => 2ϵ*σ*Tk^4 ~ track(u"W/m^2")
    R_thermal(R_wall, R_leaf): thermal_radiation_absorbed => R_wall - R_leaf ~ track(u"W/m^2")
    R_net(R_sw, R_thermal): net_radiation_absorbed => R_sw + R_thermal ~ track(u"W/m^2")

    Δw(T, T_air, RH, #= P_air, =# ea=vp.ambient, es=vp.saturation): leaf_vapor_pressure_gradient => begin
        Es = es(T)
        Ea = ea(T_air, RH)
        Es - Ea # MAIZSIM: / (1 - (Es + Ea) / P_air)
    end ~ track(u"kPa")
    E(gv, Δw): transpiration => gv*Δw ~ track(u"mmol/m^2/s" #= H2O =#)

    H(Cp, gh, ΔT): sensible_heat_flux => Cp*gh*ΔT ~ track(u"W/m^2")
    λE(λ, E): latent_heat_flux => λ*E ~ track(u"W/m^2")

    ΔT(R_net, H, λE): temperature_adjustment => begin
        R_net ⩵ H + λE
    end ~ bisect(lower=-5, upper=5, u"K", evalunit=u"W/m^2")

    T(T_air, ΔT): leaf_temperature => (T_air + ΔT) ~ track(u"°C")
    Tk(T): absolute_leaf_temperature ~ track(u"K")
end
