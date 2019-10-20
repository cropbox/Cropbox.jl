using Unitful

@system Pedotransfer begin
    tension_wilting_point: Ψ_wp => 1500 ~ preserve(u"kPa", parameter)
    tension_field_capacity: Ψ_fc => 33 ~ preserve(u"kPa", parameter)
    tension_saturation: Ψ_sat => 0.01 ~ preserve(u"kPa", parameter)

    vwc_wilting_point: θ_wp ~ hold
    vwc_field_capacity: θ_fc ~ hold
    vwc_saturation: θ_sat ~ hold

    hydraulic_conductivity_at(; vwc): K_at ~ hold
    matric_head_at: Hm_at ~ hold
end

@system TabularPedotransfer(Pedotransfer) begin
    vwc2hc => [
        0.005 3.46e-9;
        0.050 4.32e-8;
        0.100 1.3e-7;
        0.150 6.91e-7;
        0.200 4.32e-6;
        0.250 2.59e-5;
        0.300 0.000173;
        0.350 0.001037;
        0.400 0.006912;
        0.450 0.0432;
        1.000 0.0432;
    ] ~ interpolate(u"m/d")
    #hc_to_vwc(vwc_to_hc) ~ interpolate(reverse)

    vwc2ss => [
        0.005 10000;
        0.010 3500;
        0.025 1000;
        0.050 200;
        0.100 40;
        0.150 10;
        0.200 6;
        0.250 3.5;
        0.300 2.2;
        0.350 1.4;
        0.400 0.56;
        0.450 0.001; #HACK: no duplicate 0
        1.000 0;
    ] ~ interpolate(u"m")
    ss2vwc(vwc2ss) ~ interpolate(reverse)

    head(; Ψ(u"kPa")) => (Ψ * u"m" / 9.8041u"kPa") ~ call(u"m")

    vwc_wilting_point(ss2vwc, head, Ψ_wp): θ_wp => ss2vwc(head(Ψ_wp)) ~ preserve # 0.02? 0.06
    vwc_field_capacity(ss2vwc, head, Ψ_fc): θ_fc => ss2vwc(head(Ψ_fc)) ~ preserve # 0.11? 0.26
    vwc_saturation(ss2vwc, head, Ψ_sat): θ_sat => ss2vwc(head(Ψ_sat)) ~ preserve # 0.45

    hydraulic_conductivity_at(vwc2hc; θ): K_at => vwc2hc(θ) ~ call(u"m/d")
    matric_head_at(vwc2ss; θ): Hm_at => vwc_ss(θ) ~ call(u"m")

    # vwc_airdry_water => 0.01 ~ preserve(parameter)
    # vwc_wilting_point => 0.07 ~ preserve(parameter)
    # initial_vwc => 0.4 ~ preserve(parameter)
    # rooting_depth => 0.2 ~ preserve(u"m", parameter)
    # iteration_per_time_step => 100 ~ preserve(parameter)
end

@system Texture begin
    sand: S => 0.29 ~ preserve(parameter)
    clay: C => 0.32 ~ preserve(parameter)
    organic_matter: OM => 1.5 ~ preserve(u"percent", parameter)
end

@system CharacteristicTransfer(Pedotransfer, Texture) begin
    density_factor: DF => 1.0 ~ preserve(parameter)

    # volumetric soil water content at permanent wilting point

    vwc_1500_first(S, C, OM): θ_1500t => begin
        -0.024S + 0.487C + 0.006OM + 0.005S*OM - 0.013C*OM + 0.068S*C + 0.031
    end ~ preserve # theta_1500t (%v)

    vwc_1500(θ=θ_1500t): θ_1500 => begin
        θ + (0.14θ - 0.02)
    end ~ preserve # theta_1500 (%v)

    vwc_wilting_point(θ_1500): θ_wp ~ preserve

    # volumetric soil water content at field capacity

    vwc_33_first(S, C, OM): θ_33t => begin
        -0.251S + 0.195C + 0.011OM + 0.006S*OM - 0.027C*OM + 0.452S*C + 0.299
    end ~ preserve # theta_33t (%v)

    vwc_33_normal(θ=θ_33t): θ_33 => begin
        θ + (1.283θ^2 - 0.374θ - 0.015)
    end ~ preserve # theta_33 (%v)

    vwc_33_adjusted(θ_33, θ_s, θ_s_DF): θ_33_DF => begin
        θ_33 - 0.2(θ_s - θ_s_DF)
    end ~ preserve # theta_33_DF (%v)

    vwc_field_capacity(θ_33_DF): θ_fc ~ preserve

    # volumetric soil water content between saturation and field capacity

    vwc_gravitation_first(S, C, OM): θ_s_33t => begin
        0.278S + 0.034C +0.022OM - 0.018S*OM - 0.027C*OM - 0.584S*C + 0.078
    end ~ preserve # theta_s_33t (%v)

    vwc_gravitation_normal(θ=θ_s_33t): θ_s_33 => begin
        θ + (0.636θ - 0.107)
    end ~ preserve # theta_s_33 (%v)

    vwc_gravitation_adjusted(θ_s_DF, θ_33_DF): θ_s_33_DF => begin
        θ_s_DF - θ_33_DF
    end ~ preserve # theta_s_33_DF (%v)

    # volumetric soil water content at saturation

    vwc_saturation_normal(θ_33, θ_s_33, S): θ_s => begin
        θ_33 + θ_s_33 - 0.097S + 0.043
    end ~ preserve # theta_s (%v)

    vwc_saturation_adjusted(θ_s, ρ_DF, ρ_P): θ_s_DF => begin
        1 - ρ_DF / ρ_P
    end ~ preserve # theta_s_DF (%v)

    vwc_saturation(θ_s_DF): θ_sat ~ preserve

    # density effects

    matric_density(ρ_N, DF): ρ_DF => begin
        ρ_N * DF
    end ~ preserve(u"g/cm^3") # rho_DF (g cm-3)

    normal_density(θ_s, ρ_P): ρ_N => begin
        (1 - θ_s) * ρ_P
    end ~ preserve(u"g/cm^3") # rho_N (g cm-3)

    particle_density: ρ_P => begin
        2.65
    end ~ preserve(u"g/cm^3") # (g cm-3)

    # hydraulic conductivity (moisture - conductivity)

    # coefficients of moisture-tension, Eq. 11 of Saxton and Rawls 2006
    moisture_tension_curve_coeff_A(B, θ_33): A => begin
        exp(log(33) + B*log(θ_33))
    end ~ preserve

    moisture_tension_curve_coeff_B(θ_33, θ_1500): B => begin
        (log(1500) - log(33)) / (log(θ_33) - log(θ_1500))
    end ~ preserve

    # slope of logarithmic tension-moisture curve
    pore_size_distribution(B): λ => begin
        1 / B
    end ~ preserve

    saturated_hydraulic_conductivity(θ_s, θ_33, λ): K_s => begin
        1930(θ_s - θ_33)^(3-λ)
    end ~ preserve(u"mm/hr") # K_s,i (m day-1)

    hydraulic_conductivity_at(K_s, θ_s, λ; θ): K_at => begin
        #TODO: need bounds check?
        # θ = min(θ, θ_s)
        # (Ψ_at(vwc) < Ψ_ae) && (θ = θ_s)
        K_s * (θ / θ_s)^(3 + 2/λ)
    end ~ call(u"mm/hr") # K_theta,i (m day-1)

    # soil matric suction (moisture - tension)

    tension_air_entry_first(S, C, OM, θ=θ_s_33): Ψ_et => begin
        -21.674S - 27.932C - 81.975θ + 71.121S*θ + 8.294C*θ + 14.05S*C + 27.161
    end ~ preserve(u"kPa") # psi_et (kPa)

    tension_air_entry(Ψ_et): Ψ_e => begin
        Ψ = ustrip(u"kPa", Ψ_et)
        Ψ_e = Ψ + (0.02Ψ^2 - 0.113Ψ - 0.70)
        #TODO: need bounds check?
        # max(Ψ_e, zero(Ψ_e))
    end ~ preserve(u"kPa") # psi_e (kPa)

    tension_at(θ_s, θ_33, θ_1500, Ψ_e, A, B; θ): Ψ_at => begin
        if θ_s <= θ
            Ψ_e
        elseif θ_33 <= θ
            33u"kPa" - (θ - θ_33) * (33u"kPa" - Ψ_e) / (θ_s - θ_33)
        elseif θ_1500 <= θ
            A*θ^-B
        else
            #@show "too low θ = $θ < θ_1500 = $θ_1500"
            A*θ^-B
        end
    end ~ call(u"kPa") # psi_theta (kPa)

    matric_head_at(Ψ_at; θ): Hm_at => begin
        Ψ_at(θ) * u"m" / 9.8041u"kPa"
    end ~ call(u"m") # H_mi (m)
end

#TODO: support convenient way to set up custom Clock
#TODO: support unit reference again?
import Cropbox: Clock, Context, Config, Queue
@system SoilClock(Clock) begin
    step => 15u"minute" ~ preserve(u"hr", parameter)
end
@system SoilContext(Context) begin
    context ~ ::Context(override)
    clock(config) ~ ::SoilClock
end

#TODO: implement LayeredTexture for customization
@system Layer(CharacteristicTransfer) begin
    context ~ ::SoilContext(override)

    index: i ~ ::Int(override)
    vwc_initial: θ_i => 0.4 ~ preserve(extern)

    # Soil layer depth and cumulative thickness (2.4.2)
    depth: z ~ preserve(u"m", extern) # z_i (m)
    rooting_depth: d_r ~ track(u"m", override) # d_root (m)

    thickness: s ~ preserve(u"m", extern) # s_i (m)
    cumulative_thickness: ss ~ preserve(u"m", extern) # S_i (m)

    root_zone_thickness(s, ss, d_r): s_r => begin
        z = zero(d_r)
        max(s - max(ss - d_r, z), z)
    end ~ track(u"m") # s_i | s_i - (S_i - d_root) (m)

    water_content_root_zone(θ, s_r): 𝚯_r => θ * s_r ~ track(u"m") # Theta_root,i (m) (Eq. 2.95)
    water_content_root_zone_wilting_point(θ_wp, s_r): 𝚯_r_wp => θ_wp * s_r ~ track(u"m")
    water_content_root_zone_field_capacity(θ_fc, s_r): 𝚯_r_fc => θ_fc * s_r ~ track(u"m")
    water_content_root_zone_saturation(θ_sat, s_r): 𝚯_r_sat => θ_sat * s_r ~ track(u"m")

    # Root extraction of water (2.4.5)
    water_extraction_ratio(z, d_r): ϕ => begin
        cj = iszero(d_r) ? 0 : min(1, z / d_r)
        1.8cj - 0.8cj^2
    end ~ track # phi_i

    # Hydraulic conductivity (2.4.6)
    hydraulic_conductivity(K_at, θ): K => K_at(θ) ~ track(u"m/d") # k_i (m day-1)

    # Matric suction head (2.4.7)
    matric_head(Hm_at, θ): Hm => Hm_at(θ) ~ track(u"m") # H_mi (m)

    # Gravity head (2.4.8)
    gravity_head(z): Hg ~ preserve(u"m") # H_gi (m)

    # Total head
    total_head(Hm, Hg): H => Hm + Hg ~ track(u"m") # H_i (m)

    # Water content (2.4.10)
    water_flux_in: qi => 0 ~ track(u"m/d", skip) # q_i (m day-1)
    water_flux_out: qo => 0 ~ track(u"m/d", skip) # q_o (m day-1)
    water_flux_net(qi, qo): q̂ => qi - qo ~ track(u"m/d") # q^hat_i (m day-1)
    water_content(q̂): 𝚯 ~ accumulate(init=𝚯_i, u"m") # Theta_i (m)

    water_content_initial(θ_i, s): 𝚯_i => θ_i * s ~ preserve(u"m")
    water_content_wilting_point(θ_wp, s): 𝚯_wp => θ_wp * s ~ track(u"m")
    water_content_field_capacity(θ_fc, s): 𝚯_fc => θ_fc * s ~ track(u"m")
    water_content_saturation(θ_sat, s): 𝚯_sat => θ_sat * s ~ track(u"m")

    # Volumetric water content (-)
    volumetric_water_content(i, 𝚯, 𝚯_wp, 𝚯_sat, s): θ => begin
        #FIXME: remove clamping?
        #HACK: clamping only for vwc
        # Teh uses 0.005 m3/m3 instead of wilting point
        #𝚯 = clamp(𝚯, 𝚯_wp, 𝚯_sat)
        θ = min(𝚯, 𝚯_sat) / s
        θ = max(θ, 0.005)
    end ~ track # Theta_v,i (m3 m-3)
end

@system SurfaceInterface begin
    context ~ ::SoilContext(override)
    layer: l ~ ::Layer(override)

    precipitation: R ~ track(u"m/d", override)
    evaporation_actual: Ea ~ track(u"m/d", override)
    transpiration_actual: Ta ~ track(u"m/d", override)

    water_extraction(Ta, ϕ=l.ϕ): Tai => begin
        Ta * ϕ
    end ~ track(u"m/d")

    flux(R, Ea, Tai): q => begin
        R - Ea - Tai
    end ~ track(u"m/d")

    _flux(l, q) => begin
        Cropbox.setvar!(l, :water_flux_in, q)
    end ~ ::Nothing
end

@system SoilInterface begin
    context ~ ::SoilContext(override)
    upper_layer: l1 ~ ::Layer(override)
    lower_layer: l2 ~ ::Layer(override)

    transpiration_actual: Ta ~ track(u"m/d", override)

    hydraulic_conductivity(K1=l1.K, K2=l2.K, s1=l1.s, s2=l2.s): K => begin
        ((K1*s1) + (K2*s2)) / (s1 + s2)
    end ~ track(u"m/d") # k^bar (m day-1)

    # Hydraulic gradient (2.4.9)
    hydraulic_gradient(H1=l1.H, H2=l2.H): ΔH => begin
        H2 - H1
    end ~ track(u"m") # (m)

    depth_gradient(z1=l1.z, z2=l2.z): Δz => begin
        z2 - z1
    end ~ track(u"m") # (m)

    water_extraction(Ta, ϕ1=l1.ϕ, ϕ2=l2.ϕ): Tai => begin
        Ta * (ϕ2 - ϕ1)
    end ~ track(u"m/d")

    flux(K, ΔH, Δz, Tai): q => begin
        K * (ΔH / Δz) - Tai
    end ~ track(u"m/d") # q_i (m day-1)

    _flux(l1, l2, q) => begin
        Cropbox.setvar!(l1, :water_flux_out, q)
        Cropbox.setvar!(l2, :water_flux_in, q)
    end ~ ::Nothing
end

@system BedrockInterface begin
    context ~ ::SoilContext(override)
    layer: l ~ ::Layer(override)

    flux(l.K): q ~ track(u"m/d")

    _flux(l, q) => begin
        Cropbox.setvar!(l, :water_flux_out, q)
    end ~ ::Nothing
end

using DataFrames
using CSV
@system Weather begin
    filename => "PyWaterBal.csv" ~ preserve::String(parameter)
    index => :timestamp ~ preserve::Symbol(parameter)

    dataframe(filename, index): df => begin
        df = CSV.read(filename)
        df[!, index] = map(eachrow(df)) do r
            (r.timestamp - 1) * u"d"
        end
        df
    end ~ preserve::DataFrame
    key(t=context.clock.tick) ~ track(u"d")
    store(df, index, key): s => begin
        df[df[!, index] .== key, :][1, :]
    end ~ track::DataFrameRow{DataFrame,DataFrames.Index}
    #Dict(:precipitation => 0.3, transpiration => 0.1, evaporation => 0.1)

    precipitation(s): R => s[:precipitation] ~ track(u"mm/d")
    transpiration(s): T => s[:transpiration] ~ track(u"mm/d")
    evaporation(s): E => s[:evaporation] ~ track(u"mm/d")
end

# w = instance(Weather, config=configure(
#     :Clock => (:step => 24),
#     :Weather => (:filename => "test/PyWaterBal.csv")
# ))

#FIXME: not just SoilClock, but entire Context should be customized for sub-timestep handling
#TODO: implement sub-timestep advance
# 2.4.11 Daily integration
# iterations=100
# Theta_i,t+1 (m day-1) (Eq. 2.105)
@system Soil begin
    context ~ ::SoilContext(override)
    weather: w ~ ::Weather(override)

    rooting_depth: d_r ~ track(u"m", override) # d_root (m)

    # Partitioning of soil profile into several layers (2.4.1)
    layers(context, d_r): L => begin
        # Soil layer depth and cumulative thickness (2.4.2)
        n = 5
        s = 0.2u"m" # thickness
        ss = 0u"m" # cumulative_thickness
        θ = 0.4 # vwc_initial
        L = Layer[]
        for i in 1:n
            z = ss + s/2 # depth
            l = Layer(context=context, index=i, vwc_initial=θ, depth=z, rooting_depth=d_r, thickness=s, cumulative_thickness=ss)
            push!(L, l)
            ss += s
        end
        L
    end ~ ::Vector{Layer}

    surface_interface(context, layer=L[1], precipitation, evaporation_actual, transpiration_actual) ~ ::SurfaceInterface

    soil_interfaces(context, L, Ta) => begin
        [SoilInterface(context=context, upper_layer=a, lower_layer=b, transpiration_actual=Ta) for (a, b) in zip(L[1:end-1], L[2:end])]
    end ~ ::Vector{SoilInterface}

    bedrock_interface(context, layer=L[end]) ~ ::BedrockInterface

    interfaces(L, surface_interface, soil_interfaces, bedrock_interface) => begin
        [surface_interface, soil_interfaces..., bedrock_interface]
    end ~ ::Vector{System}(skip)

    # Actual evaporation (2.4.3)
    evaporation_reduction_factor(θ=L[1].θ, θ_sat=L[1].θ_sat): RD_e => begin
        1 / (1 + (3.6073 * (θ / θ_sat))^-9.3172)
    end ~ track # R_D,e
    evaporation_potential(w.E): Ep ~ track(u"m/d")
    evaporation_actual(Ep, RD_e): Ea => Ep * RD_e ~ track(u"m/d") # E_a (m day-1)

    # Actual transpiration (2.4.4)
    volumetric_water_content_root_zone(L, d_r): θ_r => begin
        sum([Cropbox.value(l.𝚯_r) for l in L]) / d_r
    end ~ track # Theta_v,root (m3 m-3)

    volumetric_water_content_root_zone_wilting_point(L, d_r): θ_r_wp => begin
        sum([Cropbox.value(l.𝚯_r_wp) for l in L]) / d_r
    end ~ track # (m3 m-3)

    volumetric_water_content_root_zone_field_capacity(L, d_r): θ_r_fc => begin
        sum([Cropbox.value(l.𝚯_r_fc) for l in L]) / d_r
    end ~ track # (m3 m-3)

    volumetric_water_content_root_zone_saturation(L, d_r): θ_r_sat => begin
        sum([Cropbox.value(l.𝚯_r_sat) for l in L]) / d_r
    end ~ track # (m3 m-3)

    transpiration_reduction_factor(θ_r, θ_r_wp, θ_r_sat): RD_t => begin
        θ_cr = (θ_r_wp + θ_r_sat) / 2
        f = (θ_r - θ_r_wp) / (θ_cr - θ_r_wp)
        #FIXME: 0 instead of 0.01?
        clamp(f, 0.01, 1)
    end ~ track # R_D,t
    transpiration_potential(w.T): Tp ~ track(u"m/d")
    transpiration_actual(Tp, RD_t): Ta => Tp * RD_t ~ track(u"m/d") # T_a (m day-1)

    precipitation(w.R): R ~ track(u"m/d")
end

@system SoilController(Controller) begin
    weather(context, config): w ~ ::Weather
    soil_context(context, config): sc ~ ::SoilContext(context)
    rooting_depth => 0.3 ~ track(u"m")
    soil(context=soil_context, weather, rooting_depth): s ~ ::Soil
end

s = instance(SoilController, config=configure(
    :Clock => (:step => 1u"d"),
    :SoilClock => (:step => 15u"minute"),
    :Weather => (:filename => "test/PyWaterBal.csv")
))
run!(s, 80, v1="s.L[1].θ", v2="s.L[2].θ", v3="s.L[3].θ", v4="s.L[4].θ", v5="s.L[5].θ")
