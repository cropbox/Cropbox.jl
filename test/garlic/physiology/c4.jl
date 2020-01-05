using Cropbox
using DataFrames
using CSV
using TimeZones
using Dates

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

@system Weather(DataFrameStore) begin
    # calendar(context) ~ ::Calendar(override)
    vapor_pressure(context): vp ~ ::VaporPressure

    index(t=nounit(context.clock.tick)) => t + 1 ~ track::Int
    timestamp(; r::DataFrameRow) => getfield(r, :row) ~ call

    photon_flux_density(s): PFD ~ drive(key=:SolRad, u"μmol/m^2/s") #Quanta
    #PFD => 1500 ~ track # umol m-2 s-1

    CO2(s) => s[:CO2] ~ track(u"μmol/mol")
    #CO2 => 400 ~ track(u"μmol/mol")

    #relative_humidity(s): RH ~ drive(key="RH", u"percent")
    relative_humidity(s): RH => s[:RH] ~ track(u"percent")
    #RH => 0.6 ~ track # 0~1

    air_temperature(s): T_air ~ drive(key=:Tair, u"°C")
    #T_air => 25 ~ track # C

    absolute_air_temperature(T_air): Tk_air ~ track(u"K")

    wind_speed(s): wind ~ drive(key=:Wind, u"m/s")
    #wind => 2.0 ~ track # meters s-1

    #TODO: make P_air parameter?
    air_pressure: P_air => 100 ~ track(u"kPa")

    vapor_pressure_deficit(T_air, RH, D=vp.D): VPD => D(T_air, RH) ~ track(u"kPa")
    vapor_pressure_saturation_slope_delta(T_air, Δ=vp.Delta): VPD_slope_delta => Δ(T_air) ~ track(u"kPa/K")
    vapor_pressure_saturation_slope(T_air, P_air, s=vp.s): VPD_slope => s(T_air, P_air) ~ track(u"K^-1")
end

#TODO implement proper soil module
@system Soil begin
    T_soil => 10 ~ track(u"°C")
    leaf_water_potential: WP_leaf => 0 ~ preserve(u"MPa", parameter) # pressure - leaf water potential MPa...
    total_root_weight => 0 ~ track(u"g")
end

quadratic_solve_upper(a, b, c) = begin
    (a == 0) && return 0.
    v = b^2 - 4a*c
    (v < 0) ? -b/a : (-b + sqrt(v)) / 2a
end
quadratic_solve_lower(a, b, c) = begin
    (a == 0) && return 0.
    v = b^2 - 4a*c
    (v < 0) ? -b/a : (-b - sqrt(v)) / 2a
end

@system C4 begin
    Ci: intercellular_co2 ~ hold
    I2: effective_irradiance ~ hold
    T: leaf_temperature ~ hold
    N: nitrogen ~ hold

    Cm(Ci): mesophyll_co2 ~ track(u"μbar")
    Tk(T): absolute_leaf_temperature ~ track(u"K")

    # FIXME are they even used?
    # beta_ABA => 1.48e2 # Tardieu-Davies beta, Dewar (2002) Need the references !?
    # delta => -1.0
    # alpha_ABA => 1.0e-4
    # lambda_r => 4.0e-12 # Dewar's email
    # lambda_l => 1.0e-12
    # K_max => 6.67e-3 # max. xylem conductance (mol m-2 s-1 MPa-1) from root to leaf, Dewar (2002)

    gbs => 0.003 ~ preserve(u"mol/m^2/s/bar" #= CO2 =#, parameter) # bundle sheath conductance to CO2, mol m-2 s-1
    # gi => 1.0 ~ preserve(parameter) # conductance to CO2 from intercelluar to mesophyle, mol m-2 s-1, assumed

    # Arrhenius equation
    Tb: base_temperature => 25 ~ preserve(u"°C", parameter)
    Tbk(Tb): absolute_base_temperature ~ preserve(u"K", parameter)
    T_dep(T, Tk, Tb, Tbk; Ea(u"kJ/mol")): temperature_dependence_rate => begin
        exp(Ea * (T - Tb) / (Tbk * u"R" * Tk))
    end ~ call

    s => 2.9 ~ preserve(parameter)
    N0 => 0.25 ~ preserve(parameter)
    N_dep(N, s, N0): nitrogen_limited_rate => begin
        2 / (1 + exp(-s * (max(N0, N) - N0))) - 1
    end ~ track

    # Rd25: Values in Kim (2006) are for 31C, and the values here are normalized for 25C. SK
    Rd25: dark_respiration_at_25 => 2 ~ preserve(u"μmol/m^2/s" #= O2 =#, parameter)
    Ear: activation_energy_for_respiration => 39.8 ~ preserve(u"kJ/mol", parameter)
    Rd(T_dep, Rd25, Ear): dark_respiration => begin
        Rd25 * T_dep(Ear)
    end ~ track(u"μmol/m^2/s")

    Rm(Rd) => 0.5Rd ~ track(u"μmol/m^2/s")

    Jm25: maximum_electron_transport_rate_at_25 => 300 ~ preserve(u"μmol/m^2/s" #= Electron =#, parameter)
    Eaj: activation_energy_for_electron_transport => 32.8 ~ preserve(u"kJ/mol", parameter)
    Sj: electron_transport_temperature_response => 702.6 ~ preserve(u"J/mol/K", parameter)
    Hj: electron_transport_curvature => 220 ~ preserve(u"kJ/mol", parameter)
    Jmax(Tk, Tbk, T_dep, N_dep, Jm25, Eaj, Sj, Hj): maximum_electron_transport_rate => begin
        R = u"R"
        Jm25 * begin
            N_dep *
            T_dep(Eaj) *
            (1 + exp((Sj*Tbk - Hj) / (R*Tbk))) /
            (1 + exp((Sj*Tk  - Hj) / (R*Tk)))
        end
    end ~ track(u"μmol/m^2/s" #= Electron =#)

    # mesophyll O2 partial pressure
    Om: mesophyll_o2_partial_pressure => 210 ~ preserve(u"mbar", parameter)

    # Kp25: Michaelis constant for PEP caboxylase for CO2
    Kp25: pep_carboxylase_constant_for_co2_at_25 => 80 ~ preserve(u"μbar", parameter)
    Kp(Kp25): pep_carboxylase_constant_for_co2 => begin
        Kp25 # T dependence yet to be determined
    end ~ track(u"μbar")

    # Kc25: Michaelis constant of rubisco for CO2 of C4 plants (2.5 times that of tobacco), ubar, Von Caemmerer 2000
    Kc25: rubisco_constant_for_co2_at_25 => 650 ~ preserve(u"μbar", parameter)
    Eac: activation_energy_for_co2 => 59.4 ~ preserve(u"kJ/mol", parameter)
    Kc(T_dep, Kc25, Eac): rubisco_constant_for_co2 => begin
        Kc25 * T_dep(Eac)
    end ~ track(u"μbar")

    # Ko25: Michaelis constant of rubisco for O2 (2.5 times C3), mbar
    Ko25: rubisco_constant_for_o2_at_25 => 450 ~ preserve(u"mbar", parameter)
    # Activation energy for Ko, Bernacchi (2001)
    Eao: activation_energy_for_o2 => 36 ~ preserve(u"kJ/mol", parameter)
    Ko(T_dep, Ko25, Eao): rubisco_constant_for_o2 => begin
        Ko25 * T_dep(Eao)
    end ~ track(u"mbar")

    Km(Kc, Om, Ko) => begin
        # effective M-M constant for Kc in the presence of O2
        Kc * (1 + Om / Ko)
    end ~ track(u"μbar")

    Vpm25: maximum_pep_carboxylation_rate_for_co2_at_25 => 70 ~ preserve(u"μmol/m^2/s" #= CO2 =#, parameter)
    EaVp: activation_energy_for_pep_carboxylation => 75.1 ~ preserve(u"kJ/mol", parameter)
    Vpmax(N_dep, T_dep, Vpm25, EaVp): maximum_pep_carboxylation_rate => begin
        Vpm25 * N_dep * T_dep(EaVp)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    # PEP regeneration limited Vp, value adopted from vC book
    Vpr: regeneration_limited_pep_carboxylation_rate => 80 ~ preserve(u"μmol/m^2/s", parameter)

    Vp(Vpmax, Vpr, Cm, Kp): pep_carboxylation_rate => begin
        # PEP carboxylation rate, that is the rate of C4 acid generation
        Vp = (Cm * Vpmax) / (Cm + Kp)
        clamp(Vp, zero(Vp), Vpr)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    Vcm25: maximum_carboxylation_rate_at_25 => 50 ~ preserve(u"μmol/m^2/s" #= CO2 =#, parameter)
    # EaVc: Sage (2002) JXB
    EaVc: activation_energy_for_carboxylation => 55.9 ~ preserve(u"kJ/mol", parameter)
    Vcmax(N_dep, T_dep, Vcm25, EaVc): maximum_carboxylation_rate => begin
        Vcm25 * N_dep * T_dep(EaVc)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    Ac(Vp, gbs, Cm, Rm, Vcmax, Rd): enzyme_limited_photosynthesis_rate => begin
        # Enzyme limited A (Rubisco or PEP carboxylation)
        Ac1 = Vp + gbs*Cm - Rm
        #Ac1 = max(0, Ac1) # prevent Ac1 from being negative Yang 9/26/06
        Ac2 = Vcmax - Rd
        min(Ac1, Ac2)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    # θ: sharpness of transition from light limitation to light saturation
    θ: light_transition_sharpness => 0.5 ~ preserve(parameter)
    J(I2, Jmax, θ): electron_transport_rate => begin
        a = θ
        b = -(I2+Jmax) |> u"μmol/m^2/s" |> ustrip
        c = I2*Jmax |> u"(μmol/m^2/s)^2" |> ustrip
        quadratic_solve_lower(a, b, c)
    end ~ track(u"μmol/m^2/s")

    # x: Partitioning factor of J, yield maximal J at this value
    x: electron_transport_partitioning_factor => 0.4 ~ preserve(parameter)
    # Light and electron transport limited A mediated by J
    Aj(J, Rd, Rm, gbs, Cm, x): transport_limited_photosynthesis_rate => begin
        Aj1 = x * J/2 - Rm + gbs*Cm
        Aj2 = (1-x) * J/3 - Rd
        min(Aj1, Aj2)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    # smooting the transition between Ac and Aj
    β: photosynthesis_transition_factor => 0.99 ~ preserve(parameter)
    A_net(Ac, Aj, β): net_photosynthesis => begin
        ((Ac+Aj) - sqrt((Ac+Aj)^2 - 4β*Ac*Aj)) / 2β
    end ~ track(u"μmol/m^2/s" #= CO2 =#)
    
    A_gross(A_net, Rd): gross_photosynthesis => begin
        A_gross = A_net + Rd
        # gets negative when PFD = 0, Rd needs to be examined, 10/25/04, SK
        #max(A_gross, zero(A_gross))
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    #FIXME: currently not used variables

    # alpha: fraction of PSII activity in the bundle sheath cell, very low for NADP-ME types
    α: bundle_sheath_PSII_activity_fraction => 0.0001 ~ preserve(parameter)
    # Bundle sheath O2 partial pressure, mbar
    Os(A_net, gbs, Om, α): bundle_sheath_o2 => begin
        α * A_net / (0.047gbs) + Om
    end ~ track(u"mbar")

    Cbs(A_net, Vp, Cm, Rm, gbs): bundle_sheath_co2 => begin
        Cm + (Vp - A_net - Rm) / gbs # Bundle sheath CO2 partial pressure, ubar
    end ~ track(u"μbar")

    # half the reciprocal of rubisco specificity, to account for O2 dependence of CO2 comp point,
    # note that this become the same as that in C3 model when multiplied by [O2]
    Γ1 => 0.193 ~ preserve(parameter)
    Γ★(Γ1, Os) => Γ1 * Os ~ track(u"μbar")
    Γ(Rd, Km, Vcmax, Γ★) => begin
        (Rd*Km + Vcmax*Γ★) / (Vcmax - Rd)
    end ~ track(u"μbar")
end

@system BoundaryLayer begin
    weather ~ hold

    w: leaf_width => 0.1 ~ preserve(u"m", parameter)

    # maize is an amphistomatous species, assume 1:1 (adaxial:abaxial) ratio.
    #sr = 1.0
    # switchgrass adaxial : abaxial (Awada 2002)
    # https://doi.org/10.4141/P01-031
    #sr = 1.28
    sr: stomatal_ratio => 1.0 ~ preserve(parameter)
    scr(sr): sides_conductance_ratio => ((sr + 1)^2 / (sr^2 + 1)) ~ preserve

    # multiply by 1.4 for outdoor condition, Campbell and Norman (1998), p109
    ocr: outdoor_conductance_ratio => 1.4 ~ preserve

    u(u=weather.wind): wind_velocity => max(u, 0.1u"m/s") ~ track(u"m/s")
    # characteristic dimension of a leaf, leaf width in m
    d(w): characteristic_dimension => 0.72w ~ track(u"m")
    v: kinematic_viscosity_of_air_at_20 => 1.51e-5 ~ preserve(u"m^2/s", parameter)
    κ: thermal_diffusivity_of_air_at_20 => 21.5e-6 ~ preserve(u"m^2/s", parameter)
    Re(u, d, v): reynolds_number => u*d/v ~ track
    Nu(Re): nusselt_number => 0.60sqrt(Re) ~ track
    gh(κ, Nu, d, scr, ocr, P_air=weather.P_air, Tk_air=weather.Tk_air): boundary_layer_heat_conductance => begin
        g = κ * Nu / d
        # multiply by ratio to get the effective blc (per projected area basis), licor 6400 manual p 1-9
        g *= scr * ocr
        # including a multiplier for conversion from mm s-1 to mol m-2 s-1
        g * P_air / (u"R" * Tk_air)
    end ~ track(u"mmol/m^2/s")
    # 1.1 is the factor to convert from heat conductance to water vapor conductance, an avarage between still air and laminar flow (see Table 3.2, HG Jones 2014)
    gb(gh, P_air=weather.P_air): boundary_layer_conductance => 0.147/0.135*gh / P_air ~ track(u"mol/m^2/s/bar" #= H2O =#)
end

@system Stomata begin
    weather ~ hold
    soil ~ hold
    gb: boundary_layer_conductance ~ hold
    A_net: net_photosynthesis ~ hold

    # Ball-Berry model parameters from Miner and Bauerle 2017, used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
    g0 => 0.017 ~ preserve(u"mol/m^2/s/bar" #= H2O =#, parameter)
    g1 => 4.53 ~ preserve(parameter)

    drb: diffusivity_ratio_boundary_layer => 1.37 ~ preserve(#= u"H2O/CO2", =# parameter)
    dra: diffusivity_ratio_air => 1.6 ~ preserve(#= u"H2O/CO2", =# parameter)

    Ca(CO2=weather.CO2, P=weather.P_air): co2_air => (CO2 * P) ~ track(u"μbar")
    # surface CO2 in mole fraction
    Cs(Ca, drb, A_net, gb): co2_at_leaf_surface => begin
        Ca - (drb * A_net / gb)
        # gamma: 10.0 for C4 maize
        #max(Cs, gamma)
    end ~ track(u"μbar")

    hs(g0, g1, gb, m, A_net, Cs, RH=weather.RH): relative_humidity_at_leaf_surface => begin
        a = m * g1 * A_net / Cs |> u"mol/m^2/s/bar" |> ustrip
        b = g0 + gb - (m * g1 * A_net / Cs) |> u"mol/m^2/s/bar" |> ustrip
        c = (-RH * gb) - g0 |> u"mol/m^2/s/bar" |> ustrip
        #FIXME: check unit
        hs = quadratic_solve_upper(a, b, c) |> u"percent"
        #TODO: need to prevent bifurcation?
        #clamp(hs, 0.1, 1.0)
    end ~ track(u"percent")

    # stomatal conductance for water vapor in mol m-2 s-1
    gs(g0, g1, m, A_net, hs, Cs): stomatal_conductance => begin
        gs = g0 + (g1 * m * (A_net * hs / Cs))
        max(gs, g0)
    end ~ track(u"mol/m^2/s/bar" #= H2O =#)

    LWP(soil.WP_leaf): leaf_water_potential ~ track(u"MPa")
    sf => 2.3 ~ preserve(u"MPa^-1", parameter)
    ϕf => -2.0 ~ preserve(u"MPa", parameter)
    m(LWP, sf, ϕf): [leafp_effect, transpiration_reduction_factor] => begin
        (1 + exp(sf * ϕf)) / (1 + exp(sf * (ϕf - LWP)))
    end ~ track

    gv(gs, gb): total_conductance_h2o => begin
        gs * gb / (gs + gb)
    end ~ track(u"mol/m^2/s/bar" #= H2O =#)

    rbc(gb, drb): boundary_layer_resistance_co2 => begin
        drb / gb
    end ~ track(u"m^2*s/mol*bar")

    rsc(gs, dra): stomatal_resistance_co2 => begin
        dra / gs
    end ~ track(u"m^2*s/mol*bar")

    rvc(rbc, rsc): total_resistance_co2 => begin
        rbc + rsc
    end ~ track(u"m^2*s/mol*bar")
end

@system GasExchange(BoundaryLayer, Stomata, C4) begin
    weather ~ ::Weather(override)
    soil ~ ::Soil(override)

    Cimax(Ca): intercellular_co2_upper_limit => 4Ca ~ track(u"μbar")
    Cimin: intercellular_co2_lower_limit => 0 ~ preserve(u"μbar")
    Ci(Ca, A_net, CO2=weather.CO2, rvc): intercellular_co2 => begin
        Ca - A_net * rvc
    end ~ solve(lower=Cimin, upper=Cimax, u"μbar")

    #FIXME: confusion between PFD vs. PPFD
    PPFD: photosynthetic_photon_flux_density ~ track(u"μmol/m^2/s" #= Quanta =#, override)

    # leaf reflectance + transmittance
    δ: leaf_scattering => 0.15 ~ preserve(parameter)
    f: leaf_spectral_correction => 0.15 ~ preserve(parameter)

    Ia(PPFD, δ): absorbed_irradiance => begin
        PPFD * (1 - δ)
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    I2(Ia, f): effective_irradiance => begin
        Ia * (1 - f) / 2 # useful light absorbed by PSII
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    ϵ: leaf_thermal_emissivity => 0.97 ~ preserve(parameter)
    σ: stefan_boltzmann_constant => u"σ" ~ preserve(u"W/m^2/K^4", parameter)
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

    NIR(PAR): near_infrared_radiation => begin
        # If total solar radiation unavailable, assume NIR the same energy as PAR waveband
        PAR
    end ~ track(u"W/m^2")

    # solar radiation absorptivity of leaves: =~ 0.5
    α: absorption_coefficient => 0.5 ~ preserve(parameter)

    R_light(PAR, NIR, α, δ): radiation_absorbed_from_light => begin
        # shortwave radiation (PAR (=0.85) + NIR (=0.15))
        α*((1-δ)*PAR + δ*NIR)
    end ~ track(u"W/m^2")

    R_wall(ϵ, σ, Tk_air): radiation_absorbed_from_wall => begin
        ϵ*σ*Tk_air^4
    end ~ track(u"W/m^2")

    R_in(R_light, R_wall): radiation_absored => begin
        # times 2 for projected area basis
        2(R_light + R_wall)
    end ~ track(u"W/m^2")

    R_out(ϵ, σ, Tk): radiation_emitted => begin
        2(ϵ*σ*Tk^4)
    end ~ track(u"W/m^2")

    R_net(R_in, R_out): net_radiation_absorbed => R_in - R_out ~ track(u"W/m^2")

    λE(λ, gv, VPD=weather.VPD): latent_heat_flux => begin
        λ*gv*VPD
    end ~ track(u"W/m^2")

    #FIXME: come up with a better name? (i.e. heat capacity = J(/kg)/K))
    C(Cp, ghr, λ, gv, VPD_slope_delta=weather.VPD_slope_delta): sensible_heat_capacity => begin
        Cp*ghr + λ*gv*VPD_slope_delta
    end ~ track(u"W/m^2/K")

    T_adj(R_net, λE, C): temperature_adjustment => begin
        # eqn 14.6b linearized form using first order approximation of Taylor series
        #(γ★ / (VPD_slope_delta + γ★)) * (R_net / (Cp*ghr) - VPD/γ★)
        (R_net - λE) / C
    end ~ solve(lower=-10u"K", upper=10u"K", u"K")

    T_air(weather.T_air): air_temperature ~ track(u"°C")
    Tk_air(weather.Tk_air): absolute_air_temperature ~ track(u"K")
    P_air(weather.P_air): air_pressure ~ track(u"kPa")

    T(T_adj, T_air): leaf_temperature => T_air + T_adj ~ track(u"°C")
    Tk(T): absolute_leaf_temperature ~ track(u"K")

    ET(gv, T, T_air, P_air, RH=weather.RH, ea=weather.vp.ambient, es=weather.vp.saturation): evapotranspiration => begin
        Es = es(T)
        Ea = ea(T_air, RH)
        ET = gv * ((Es - Ea) / P_air) / (1 - (Es + Ea) / P_air) * P_air
        max(ET, zero(ET)) # 04/27/2011 dt took out the 1000 everything is moles now
    end ~ track(u"mmol/m^2/s" #= H2O =#)

    N: nitrogen => 2.0 ~ preserve(parameter)
end

@system GasExchangeController(Controller) begin
    ge(context, weather, soil, PPFD) ~ ::GasExchange
    #calendar(context) ~ ::Calendar
    weather(context#=, calendar =#) ~ ::Weather
    soil(context) ~ ::Soil
    PPFD(weather.PFD) ~ track(u"μmol/m^2/s")
end

df_c = DataFrame(SolRad=1500, CO2=0:10:1500, RH=60, Tair=25, Wind=2.0)
df_t = DataFrame(SolRad=1500, CO2=400, RH=60, Tair=-10:50, Wind=2.0)
df_i = DataFrame(SolRad=0:100:3000, CO2=400, RH=60, Tair=25, Wind=2.0)
df = df_t

config = (
    #:Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
    :Weather => (:dataframe => df, :indexkey => nothing),
    :Soil => :WP_leaf => 2.0,
)

#res = simulate(GasExchangeController, stop=nrow(df)-2, target=["ge.A_net"], config=config)
#res = simulate(GasExchangeController, stop=nrow(df)-2, base="ge", target=[:A_net, :Ac, :Aj, :gs, :Ca, :Ci], index=["context.clock.tick", "weather.CO2", "weather.T_air", "weather.PFD"], config=config, nounit=true)

#config = ()

# config += """
# # Kim et al. (2007), Kim et al. (2006)
# # In von Cammerer (2000), Vpm25=120, Vcm25=60,Jm25=400
# # In Soo et al.(2006), under elevated C5O2, Vpm25=91.9, Vcm25=71.6, Jm25=354.2 YY
# C4.Vpm25 = 70
# C4.Vcm25 = 50
# C4.Jm25 = 300
# C4.Rd25 = 2 # Values in Kim (2006) are for 31C, and the values here are normalized for 25C. SK
# """

# config += """
# [C4]
# # switgrass params from Albaugha et al. (2014)
# # https://doi.org/10.1016/j.agrformet.2014.02.013
# C4.Vpm25 = 52
# C4.Vcm25 = 26
# C4.Jm25 = 145
# """

# config += """
# # switchgrass Vcmax from Le et al. (2010), others multiplied from Vcmax (x2, x5.5)
# C4.Vpm25 = 96
# C4.Vcm25 = 48
# C4.Jm25 = 264
# """

# config += """
# C4.Vpm25 = 100
# C4.Vcm25 = 50
# C4.Jm25 = 200
# """

# config += """
# C4.Vpm25 = 70
# C4.Vcm25 = 50
# C4.Jm25 = 180.8
# """

# config += """
# # switchgrass params from Albaugha et al. (2014)
# C4.Rd25 = 3.6 # not sure if it was normalized to 25 C
# C4.θ = 0.79
# """

# config += """
# # In Sinclair and Horie, Crop Sciences, 1989
# C4.s = 4
# C4.N0 = 0.2
# # In J Vos et al. Field Crop Research, 2005
# C4.s = 2.9
# C4.N0 = 0.25
# # In Lindquist, Weed Science, 2001
# C4.s = 3.689
# C4.N0 = 0.5
# """

# config += """
# # in P. J. Sellers, et al.Science 275, 502 (1997)
# # g0 is b, of which the value for c4 plant is 0.04
# # and g1 is m, of which the value for c4 plant is about 4 YY
# Stomata.g0 = 0.04
# Stomata.g1 = 4.0
# """

# config += """
# # Ball-Berry model parameters from Miner and Bauerle 2017, used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
# Stomata.g0 = 0.017
# Stomata.g1 = 4.53
# """

# config += """
# # calibrated above for our switchgrass dataset
# Stomata.g0 = 0.04
# Stomata.g1 = 1.89
# """

# config += """
# Stomata.g0 = 0.02
# Stomata.g1 = 2.0
# """

# config += """
# # parameters from Le et. al (2010)
# Stomata.g0 = 0.008
# Stomata.g1 = 8.0
# """

# config += """
# # for garlic
# Stomata.g0 = 0.0096
# Stomata.g1 = 6.824
# """

# config += """
# Stomata.sf = 2.3 # sensitivity parameter Tuzet et al. 2003 Yang
# Stomata.ϕf = -1.2 # reference potential Tuzet et al. 2003 Yang
# """

# config += """
# #? = -1.68 # minimum sustainable leaf water potential (Albaugha 2014)
# # switchgrass params from Le et al. (2010)
# Stomata.sf = 6.5
# Stomata.ϕf = -1.3
# """

# config += """
# #FIXME August-Roche-Magnus formula gives slightly different parameters
# # https://en.wikipedia.org/wiki/Clausius–Clapeyron_relation
# VaporPressure.a = 0.61094 # kPa
# VaporPressure.b = 17.625 # C
# VaporPressure.c = 243.04 # C
# """
