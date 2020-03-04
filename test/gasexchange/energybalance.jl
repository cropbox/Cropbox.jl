@system EnergyBalance(WeatherStub) begin
    gv ~ hold
    gh ~ hold
    PPFD ~ hold
    #δ ~ hold #FIXME: really needed?

    ϵ: leaf_thermal_emissivity => 0.97 ~ preserve(parameter)
    σ: stefan_boltzmann_constant => u"σ" ~ preserve(u"W/m^2/K^4")
    λ: latent_heat_of_vaporiztion_at_25 => 44 ~ preserve(u"kJ/mol", parameter)
    Cp: specific_heat_of_air => 29.3 ~ preserve(u"J/mol/K", parameter)

    # psychrometric constant (C-1) ~ 6.66e-4
    γ(Cp, λ): psychrometric_constant => (Cp / λ) ~ preserve(u"K^-1")

    #TODO: check units of two psychrometric constants
    # apparent psychrometer constant
    γ★(γ, ghr, gv): apparent_psychrometric_constant => (γ * ghr / gv) ~ preserve(u"kPa/K")

    # see Campbell and Norman (1998) pp 224-225
    # because Stefan-Boltzman constant is for unit surface area by denifition,
    # all terms including sbc are multilplied by 2 (i.e., gr, thermal radiation)
    gr(Tk, ϵ, σ, Cp): leaf_surface_radiative_conductance => begin
        # radiative conductance, 2 account for both sides
        g = 4ϵ*σ*Tk^3 / Cp
        2g
    end ~ track(u"mmol/m^2/s" #= H2O =#)

    ghr(gh, gr): total_radiative_conductance => gh + gr ~ track(u"mmol/m^2/s" #= H2O =#)

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
    R_thermal(R_wall, R_leaf): thermal_radiation_absored => R_wall - R_leaf ~ track(u"W/m^2")

    R_net(R_sw, R_thermal): net_radiation_absorbed => R_sw + R_thermal ~ track(u"W/m^2")

    λE(λ, gv, VPD): latent_heat_flux => begin
        λ*gv*VPD
    end ~ track(u"W/m^2")

    #FIXME: come up with a better name? (i.e. heat capacity = J(/kg)/K))
    C(Cp, ghr, λ, gv, VPD_Δ): sensible_heat_capacity => begin
        Cp*ghr + λ*gv*VPD_Δ
    end ~ track(u"W/m^2/K")

    T_adj(R_net, λE, C): temperature_adjustment => begin
        # eqn 14.6b linearized form using first order approximation of Taylor series
        #(γ★ / (VPD_slope_delta + γ★)) * (R_net / (Cp*ghr) - VPD/γ★)
        (R_net - λE) / C
    end ~ bisect(lower=-10u"K", upper=10u"K", u"K")

    T(T_adj, T_air): leaf_temperature => T_air + T_adj ~ track(u"°C")
    Tk(T): absolute_leaf_temperature ~ track(u"K")
end