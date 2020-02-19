module Soil

using Cropbox

@system Pedotransfer begin
    Ψ_wp: tension_wilting_point => 1500 ~ preserve(u"kPa", parameter)
    Ψ_fc: tension_field_capacity => 33 ~ preserve(u"kPa", parameter)
    Ψ_sat: tension_saturation => 0.01 ~ preserve(u"kPa", parameter)

    θ_wp: vwc_wilting_point ~ hold
    θ_fc: vwc_field_capacity ~ hold
    θ_sat: vwc_saturation ~ hold

    K_at(; vwc): hydraulic_conductivity_at ~ hold
    Hm_at: matric_head_at ~ hold
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

    θ_wp(ss2vwc, head, Ψ_wp): vwc_wilting_point => ss2vwc(head(Ψ_wp)) ~ preserve # 0.02? 0.06
    θ_fc(ss2vwc, head, Ψ_fc): vwc_field_capacity => ss2vwc(head(Ψ_fc)) ~ preserve # 0.11? 0.26
    θ_sat(ss2vwc, head, Ψ_sat): vwc_saturation => ss2vwc(head(Ψ_sat)) ~ preserve # 0.45

    K_at(vwc2hc; θ): hydraulic_conductivity_at => vwc2hc(θ) ~ call(u"m/d")
    Hm_at(vwc2ss; θ): matric_head_at => vwc_ss(θ) ~ call(u"m")

    # vwc_airdry_water => 0.01 ~ preserve(parameter)
    # vwc_wilting_point => 0.07 ~ preserve(parameter)
    # initial_vwc => 0.4 ~ preserve(parameter)
    # rooting_depth => 0.2 ~ preserve(u"m", parameter)
    # iteration_per_time_step => 100 ~ preserve(parameter)
end

@system Texture begin
    S: sand => 0.29 ~ preserve(parameter)
    C: clay => 0.32 ~ preserve(parameter)
    OM: organic_matter => 1.5 ~ preserve(u"percent", parameter)
end

@system CharacteristicTransfer(Pedotransfer, Texture) begin
    DF: density_factor => 1.0 ~ preserve(parameter)

    # volumetric soil water content at permanent wilting point

    θ_1500t(S, C, OM): vwc_1500_first => begin
        -0.024S + 0.487C + 0.006OM + 0.005S*OM - 0.013C*OM + 0.068S*C + 0.031
    end ~ preserve # theta_1500t (%v)

    θ_1500(θ=θ_1500t): vwc_1500 => begin
        θ + (0.14θ - 0.02)
    end ~ preserve # theta_1500 (%v)

    θ_wp(θ_1500): vwc_wilting_point ~ preserve

    # volumetric soil water content at field capacity

    θ_33t(S, C, OM): vwc_33_first => begin
        -0.251S + 0.195C + 0.011OM + 0.006S*OM - 0.027C*OM + 0.452S*C + 0.299
    end ~ preserve # theta_33t (%v)

    θ_33(θ=θ_33t): vwc_33_normal => begin
        θ + (1.283θ^2 - 0.374θ - 0.015)
    end ~ preserve # theta_33 (%v)

    θ_33_DF(θ_33, θ_s, θ_s_DF): vwc_33_adjusted => begin
        θ_33 - 0.2(θ_s - θ_s_DF)
    end ~ preserve # theta_33_DF (%v)

    θ_fc(θ_33_DF): vwc_field_capacity ~ preserve

    # volumetric soil water content between saturation and field capacity

    θ_s_33t(S, C, OM): vwc_gravitation_first => begin
        0.278S + 0.034C +0.022OM - 0.018S*OM - 0.027C*OM - 0.584S*C + 0.078
    end ~ preserve # theta_s_33t (%v)

    θ_s_33(θ=θ_s_33t): vwc_gravitation_normal => begin
        θ + (0.636θ - 0.107)
    end ~ preserve # theta_s_33 (%v)

    θ_s_33_DF(θ_s_DF, θ_33_DF): vwc_gravitation_adjusted => begin
        θ_s_DF - θ_33_DF
    end ~ preserve # theta_s_33_DF (%v)

    # volumetric soil water content at saturation

    θ_s(θ_33, θ_s_33, S): vwc_saturation_normal => begin
        θ_33 + θ_s_33 - 0.097S + 0.043
    end ~ preserve # theta_s (%v)

    θ_s_DF(θ_s, ρ_DF, ρ_P): vwc_saturation_adjusted => begin
        1 - ρ_DF / ρ_P
    end ~ preserve # theta_s_DF (%v)

    θ_sat(θ_s_DF): vwc_saturation ~ preserve

    # density effects

    ρ_DF(ρ_N, DF): matric_density => begin
        ρ_N * DF
    end ~ preserve(u"g/cm^3") # rho_DF (g cm-3)

    ρ_N(θ_s, ρ_P): normal_density => begin
        (1 - θ_s) * ρ_P
    end ~ preserve(u"g/cm^3") # rho_N (g cm-3)

    ρ_P: particle_density => begin
        2.65
    end ~ preserve(u"g/cm^3") # (g cm-3)

    # hydraulic conductivity (moisture - conductivity)

    # coefficients of moisture-tension, Eq. 11 of Saxton and Rawls 2006
    A(B, θ_33): moisture_tension_curve_coeff_A => begin
        exp(log(33) + B*log(θ_33))
    end ~ preserve

    B(θ_33, θ_1500): moisture_tension_curve_coeff_B => begin
        (log(1500) - log(33)) / (log(θ_33) - log(θ_1500))
    end ~ preserve

    # slope of logarithmic tension-moisture curve
    λ(B): pore_size_distribution => begin
        1 / B
    end ~ preserve

    K_s(θ_s, θ_33, λ): saturated_hydraulic_conductivity => begin
        1930(θ_s - θ_33)^(3-λ)
    end ~ preserve(u"mm/hr") # K_s,i (m day-1)

    K_at(K_s, θ_s, λ; θ): hydraulic_conductivity_at => begin
        #TODO: need bounds check?
        # θ = min(θ, θ_s)
        # (Ψ_at(vwc) < Ψ_ae) && (θ = θ_s)
        K_s * (θ / θ_s)^(3 + 2/λ)
    end ~ call(u"mm/hr") # K_theta,i (m day-1)

    # soil matric suction (moisture - tension)

    Ψ_et(S, C, OM, θ=θ_s_33): tension_air_entry_first => begin
        -21.674S - 27.932C - 81.975θ + 71.121S*θ + 8.294C*θ + 14.05S*C + 27.161
    end ~ preserve(u"kPa") # psi_et (kPa)

    Ψ_e(Ψ_et): tension_air_entry => begin
        Ψ = Cropbox.deunitfy(Ψ_et, u"kPa")
        Ψ_e = Ψ + (0.02Ψ^2 - 0.113Ψ - 0.70)
        #TODO: need bounds check?
        # max(Ψ_e, zero(Ψ_e))
    end ~ preserve(u"kPa") # psi_e (kPa)

    Ψ_at(θ_s, θ_33, θ_1500, Ψ_e, A, B; θ): tension_at => begin
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

    Hm_at(Ψ_at; θ): matric_head_at => begin
        Ψ_at(θ) * u"m" / 9.8041u"kPa"
    end ~ call(u"m") # H_mi (m)
end

#TODO: support convenient way to set up custom Clock
#TODO: support unit reference again?
import Cropbox: Clock, Context
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

    i: index ~ ::Int(override)
    θ_i: vwc_initial => 0.4 ~ preserve(extern)

    # Soil layer depth and cumulative thickness (2.4.2)
    z: depth ~ preserve(u"m", extern) # z_i (m)
    d_r: rooting_depth ~ track(u"m", override) # d_root (m)

    s: thickness ~ preserve(u"m", extern) # s_i (m)
    ss: cumulative_thickness ~ preserve(u"m", extern) # S_i (m)

    s_r(s, ss, d_r): root_zone_thickness => begin
        z = zero(d_r)
        max(s - max(ss - d_r, z), z)
    end ~ track(u"m") # s_i | s_i - (S_i - d_root) (m)

    𝚯_r(θ, s_r): water_content_root_zone => θ * s_r ~ track(u"m") # Theta_root,i (m) (Eq. 2.95)
    𝚯_r_wp(θ_wp, s_r): water_content_root_zone_wilting_point => θ_wp * s_r ~ track(u"m")
    𝚯_r_fc(θ_fc, s_r): water_content_root_zone_field_capacity => θ_fc * s_r ~ track(u"m")
    𝚯_r_sat(θ_sat, s_r): water_content_root_zone_saturation => θ_sat * s_r ~ track(u"m")

    # Root extraction of water (2.4.5)
    ϕ(z, d_r): water_extraction_ratio => begin
        cj = iszero(d_r) ? 0 : min(1, z / d_r)
        1.8cj - 0.8cj^2
    end ~ track # phi_i

    # Hydraulic conductivity (2.4.6)
    K(K_at, θ): hydraulic_conductivity => K_at(θ) ~ track(u"m/d") # k_i (m day-1)

    # Matric suction head (2.4.7)
    Hm(Hm_at, θ): matric_head => Hm_at(θ) ~ track(u"m") # H_mi (m)

    # Gravity head (2.4.8)
    Hg(z): gravity_head ~ preserve(u"m") # H_gi (m)

    # Total head
    H(Hm, Hg): total_head => Hm + Hg ~ track(u"m") # H_i (m)

    # Water content (2.4.10)
    qi: water_flux_in => 0 ~ track(u"m/d", skip) # q_i (m day-1)
    qo: water_flux_out => 0 ~ track(u"m/d", skip) # q_o (m day-1)
    q̂(qi, qo): water_flux_net => qi - qo ~ track(u"m/d") # q^hat_i (m day-1)
    𝚯(q̂): water_content ~ accumulate(init=𝚯_i, u"m") # Theta_i (m)

    𝚯_i(θ_i, s): water_content_initial => θ_i * s ~ preserve(u"m")
    𝚯_wp(θ_wp, s): water_content_wilting_point => θ_wp * s ~ track(u"m")
    𝚯_fc(θ_fc, s): water_content_field_capacity => θ_fc * s ~ track(u"m")
    𝚯_sat(θ_sat, s): water_content_saturation => θ_sat * s ~ track(u"m")

    # Volumetric water content (-)
    θ(i, 𝚯, 𝚯_wp, 𝚯_sat, s): volumetric_water_content => begin
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
    l: layer ~ ::Layer(override)

    R: precipitation ~ track(u"m/d", override)
    Ea: evaporation_actual ~ track(u"m/d", override)
    Ta: transpiration_actual ~ track(u"m/d", override)

    Tai(Ta, ϕ=l.ϕ): water_extraction => begin
        Ta * ϕ
    end ~ track(u"m/d")

    q(R, Ea, Tai): flux => begin
        R - Ea - Tai
    end ~ track(u"m/d")

    _q(l, q) => begin
        Cropbox.setvar!(l, :qi, q)
    end ~ ::Nothing
end

@system SoilInterface begin
    context ~ ::SoilContext(override)
    l1: upper_layer ~ ::Layer(override)
    l2: lower_layer ~ ::Layer(override)

    Ta: transpiration_actual ~ track(u"m/d", override)

    K(K1=l1.K, K2=l2.K, s1=l1.s, s2=l2.s): hydraulic_conductivity => begin
        ((K1*s1) + (K2*s2)) / (s1 + s2)
    end ~ track(u"m/d") # k^bar (m day-1)

    # Hydraulic gradient (2.4.9)
    ΔH(H1=l1.H, H2=l2.H): hydraulic_gradient => begin
        H2 - H1
    end ~ track(u"m") # (m)

    Δz(z1=l1.z, z2=l2.z): depth_gradient => begin
        z2 - z1
    end ~ track(u"m") # (m)

    Tai(Ta, ϕ1=l1.ϕ, ϕ2=l2.ϕ): water_extraction => begin
        Ta * (ϕ2 - ϕ1)
    end ~ track(u"m/d")

    q(K, ΔH, Δz, Tai): flux => begin
        K * (ΔH / Δz) - Tai
    end ~ track(u"m/d") # q_i (m day-1)

    _q(l1, l2, q) => begin
        Cropbox.setvar!(l1, :qo, q)
        Cropbox.setvar!(l2, :qi, q)
    end ~ ::Nothing
end

@system BedrockInterface begin
    context ~ ::SoilContext(override)
    l: layer ~ ::Layer(override)

    q(l.K): flux ~ track(u"m/d")

    _q(l, q) => begin
        Cropbox.setvar!(l, :qo, q)
    end ~ ::Nothing
end

using DataFrames
using CSV
@system SoilWeather(DataFrameStore) begin
    filename => "PyWaterBal.csv" ~ preserve::String(parameter)

    i(t=context.clock.tick): index ~ track(u"d")
    t(; r::DataFrameRow): timestamp => begin
        (r.timestamp - 1) * u"d"
    end ~ call(u"d")

    R(s): precipitation => s[:precipitation] ~ track(u"mm/d")
    T(s): transpiration => s[:transpiration] ~ track(u"mm/d")
    E(s): evaporation => s[:evaporation] ~ track(u"mm/d")
end

# w = instance(SoilWeather, config=(
#     :Clock => (:step => 24),
#     :SoilWeather => (:filename => "test/PyWaterBal.csv")
# ))

#FIXME: not just SoilClock, but entire Context should be customized for sub-timestep handling
#TODO: implement sub-timestep advance
# 2.4.11 Daily integration
# iterations=100
# Theta_i,t+1 (m day-1) (Eq. 2.105)
@system SoilModule begin
    context ~ ::SoilContext(override)
    w: weather ~ ::SoilWeather(override)

    d_r: rooting_depth ~ track(u"m", override) # d_root (m)

    # Partitioning of soil profile into several layers (2.4.1)
    L(context, d_r): layers => begin
        # Soil layer depth and cumulative thickness (2.4.2)
        n = 5
        s = 0.2u"m" # thickness
        ss = 0u"m" # cumulative_thickness
        θ = 0.4 # vwc_initial
        L = Layer[]
        for i in 1:n
            z = ss + s/2 # depth
            l = Layer(context=context, i=i, θ_i=θ, z=z, d_r=d_r, s=s, ss=ss)
            push!(L, l)
            ss += s
        end
        L
    end ~ ::Vector{Layer}

    surface_interface(context, layer=L[1], R, Ea, Ta) ~ ::SurfaceInterface

    soil_interfaces(context, L, Ta) => begin
        [SoilInterface(context=context, l1=a, l2=b, Ta=Ta) for (a, b) in zip(L[1:end-1], L[2:end])]
    end ~ ::Vector{SoilInterface}

    bedrock_interface(context, layer=L[end]) ~ ::BedrockInterface

    interfaces(L, surface_interface, soil_interfaces, bedrock_interface) => begin
        [surface_interface, soil_interfaces..., bedrock_interface]
    end ~ ::Vector{System}(skip)

    # Actual evaporation (2.4.3)
    RD_e(θ=L[1].θ, θ_sat=L[1].θ_sat): evaporation_reduction_factor => begin
        1 / (1 + (3.6073 * (θ / θ_sat))^-9.3172)
    end ~ track # R_D,e
    Ep(w.E): evaporation_potential ~ track(u"m/d")
    Ea(Ep, RD_e): evaporation_actual => Ep * RD_e ~ track(u"m/d") # E_a (m day-1)

    # Actual transpiration (2.4.4)
    θ_r(L, d_r): volumetric_water_content_root_zone => begin
        sum([l.𝚯_r' for l in L]) / d_r
    end ~ track # Theta_v,root (m3 m-3)

    θ_r_wp(L, d_r): volumetric_water_content_root_zone_wilting_point => begin
        sum([l.𝚯_r_wp' for l in L]) / d_r
    end ~ track # (m3 m-3)

    θ_r_fc(L, d_r): volumetric_water_content_root_zone_field_capacity => begin
        sum([l.𝚯_r_fc' for l in L]) / d_r
    end ~ track # (m3 m-3)

    θ_r_sat(L, d_r): volumetric_water_content_root_zone_saturation => begin
        sum([l.𝚯_r_sat' for l in L]) / d_r
    end ~ track # (m3 m-3)

    RD_t(θ_r, θ_r_wp, θ_r_sat): transpiration_reduction_factor => begin
        θ_cr = (θ_r_wp + θ_r_sat) / 2
        f = (θ_r - θ_r_wp) / (θ_cr - θ_r_wp)
        #FIXME: 0 instead of 0.01?
        clamp(f, 0.01, 1)
    end ~ track # R_D,t
    Tp(w.T): transpiration_potential ~ track(u"m/d")
    Ta(Tp, RD_t): transpiration_actual => Tp * RD_t ~ track(u"m/d") # T_a (m day-1)

    R(w.R): precipitation ~ track(u"m/d")
end

@system SoilController(Controller) begin
    w(context, config): weather ~ ::SoilWeather
    sc(context, config): soil_context ~ ::SoilContext(context)
    d_r: rooting_depth => 0.3 ~ track(u"m")
    s(context=soil_context, w, d_r): soil ~ ::SoilModule
end

end

@testset "soil" begin
    simulate(Soil.SoilController, stop=80,
        config=(
            :Clock => (:step => 1u"d"),
            :SoilClock => (:step => 15u"minute"),
            :SoilWeather => (:filename => "soil/PyWaterBal.csv"),
        ),
        target=(
            :v1 => "s.L[1].θ",
            :v2 => "s.L[2].θ",
            :v3 => "s.L[3].θ",
            :v4 => "s.L[4].θ",
            :v5 => "s.L[5].θ",
        ),
    )
    @test r[!, :tick][end] > 80u"d"
    Cropbox.plot(ans, :tick, [:v1, :v2, :v3, :v4, :v5]) |> display
end
