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
    #TODO: more robust interface to connect Systems (i.e. type check, automatic prop defines)
    co2_mesophyll: Cm ~ hold
    #co2_mesophyll_upper_limit: Cmmax ~ hold
    light: I2 ~ hold
    temperature: T ~ hold
    nitrogen: N ~ hold

    ##############
    # Parameters #
    ##############

    # FIXME are they even used?
    # beta_ABA => 1.48e2 # Tardieu-Davies beta, Dewar (2002) Need the references !?
    # delta => -1.0
    # alpha_ABA => 1.0e-4
    # lambda_r => 4.0e-12 # Dewar's email
    # lambda_l => 1.0e-12
    # K_max => 6.67e-3 # max. xylem conductance (mol m-2 s-1 MPa-1) from root to leaf, Dewar (2002)

    gbs => 0.003 ~ preserve(parameter) # bundle sheath conductance to CO2, mol m-2 s-1
    # gi => 1.0 ~ preserve(parameter) # conductance to CO2 from intercelluar to mesophyle, mol m-2 s-1, assumed

    # Arrhenius equation
    temperature_dependence_rate(T, Tb=25; Ea): T_dep => begin
        R = 8.314 # universal gas constant (J K-1 mol-1)
        K = 273.15
        #HACK handle too low temperature values during optimization
        Tk = max(0, T + K)
        Tbk = max(0, Tb + K)
        r = exp(Ea * (T - Tb) / (Tbk * R * Tk))
        isinf(r) ? zero(r) : r
    end ~ call

    nitrogen_limited_rate(N, s=2.9, N0=0.25): N_dep => begin
        2 / (1 + exp(-s * (max(N0, N) - N0))) - 1
    end ~ track

    # Rd25: Values in Kim (2006) are for 31C, and the values here are normalized for 25C. SK
    dark_respiration(T_dep, Rd25=2, Ear=39800): Rd => begin
        Rd25 * T_dep(Ear)
    end ~ track

    Rm(Rd) => 0.5Rd ~ track

    maximum_electron_transport_rate(T, T_dep, N_dep, Jm25=300, Eaj=32800, Sj=702.6, Hj=220000): Jmax => begin
        R = 8.314

        Tb = 25
        K = 273.15
        Tk = T + K
        Tbk = Tb + K

        r = Jm25 * begin
            N_dep *
            T_dep(Eaj) *
            (1 + exp((Sj*Tbk - Hj) / (R*Tbk))) /
            (1 + exp((Sj*Tk  - Hj) / (R*Tk)))
        end
        max(0, r)
    end ~ track

    Om => begin
        # mesophyll O2 partial pressure
        O = 210 # gas units are mbar
    end ~ preserve(parameter)

    # Kp25: Michaelis constant for PEP caboxylase for CO2
    Kp(Kp25=80) => begin
        Kp25 # T dependence yet to be determined
    end ~ track

    # Kc25: Michaelis constant of rubisco for CO2 of C4 plants (2.5 times that of tobacco), ubar, Von Caemmerer 2000
    Kc(T_dep, Kc25=650, Eac=59400) => begin
        Kc25 * T_dep(Eac)
    end ~ track

    # Ko25: Michaelis constant of rubisco for O2 (2.5 times C3), mbar
    Ko(T_dep, Ko25=450, Eao=36000) => begin
        Ko25 * T_dep(Eao)
    end ~ track

    Km(Kc, Om, Ko) => begin
        # effective M-M constant for Kc in the presence of O2
        Kc * (1 + Om / Ko)
    end ~ track

    Vpmax(N_dep, T_dep, Vpm25=70, EaVp=75100) => begin
        Vpm25 * N_dep * T_dep(EaVp)
    end ~ track

    Vp(Vpmax, Cm, Kp) => begin
        # PEP carboxylation rate, that is the rate of C4 acid generation
        Vp = (Cm * Vpmax) / (Cm + Kp)
        Vpr = 80 # PEP regeneration limited Vp, value adopted from vC book
        clamp(Vp, 0, Vpr)
    end ~ track

    # EaVc: Sage (2002) JXB
    Vcmax(N_dep, T_dep, Vcm25=50, EaVc=55900) => begin
        Vcm25 * N_dep * T_dep(EaVc)
    end ~ track

    enzyme_limited_photosynthesis_rate(Vp, gbs, Cm, Rm, Vcmax, Rd): Ac => begin
        # Enzyme limited A (Rubisco or PEP carboxylation)
        Ac1 = Vp + gbs*Cm - Rm
        #Ac1 = max(0, Ac1) # prevent Ac1 from being negative Yang 9/26/06
        Ac2 = Vcmax - Rd
        #println("Ac1 = $Ac1, Ac2 = $Ac2")
        min(Ac1, Ac2)
    end ~ track

    # Light and electron transport limited A mediated by J
    # theta: sharpness of transition from light limitation to light saturation
    # x: Partitioning factor of J, yield maximal J at this value
    transport_limited_photosynthesis_rate(T, Jmax, Rd, Rm, I2, gbs, Cm, theta=0.5, x=0.4): Aj => begin
        #J = roots(Poly([I2*Jmax, -(I2+Jmax), theta])) |> minimum
        J = quadratic_solve_lower(theta, -(I2+Jmax), I2*Jmax)
        #println("Jmax = $Jmax, J = $J")
        Aj1 = x * J/2 - Rm + gbs*Cm
        Aj2 = (1-x) * J/3 - Rd
        min(Aj1, Aj2)
    end ~ track

    net_photosynthesis(Ac, Aj, beta=0.99): A_net => begin
        # smooting the transition between Ac and Aj
        A_net = ((Ac+Aj) - sqrt((Ac+Aj)^2 - 4*beta*Ac*Aj)) / (2*beta)
        #println("Ac = $Ac, Aj = $Aj, A_net = $A_net")
        A_net
    end ~ track # solve(target=Cm, lower=0, upper=Cmmax)

    #FIXME: currently not used variables

    # alpha: fraction of PSII activity in the bundle sheath cell, very low for NADP-ME types
    bundle_sheath_o2(A_net, gbs, Om, alpha=0.0001): Os => begin
        alpha * A_net / (0.047*gbs) + Om # Bundle sheath O2 partial pressure, mbar
    end ~ track

    bundle_sheath_co2(A_net, Vp, Cm, Rm, gbs): Cbs => begin
        Cm + (Vp - A_net - Rm) / gbs # Bundle sheath CO2 partial pressure, ubar
    end ~ track

    gamma(Rd, Km, Vcmax, Os) => begin
        # half the reciprocal of rubisco specificity, to account for O2 dependence of CO2 comp point,
        # note that this become the same as that in C3 model when multiplied by [O2]
        gamma1 = 0.193
        gamma_star = gamma1 * Os
        (Rd*Km + Vcmax*gamma_star) / (Vcmax - Rd)
    end ~ track
end

@system Stomata begin
    weather ~ hold
    soil ~ hold
    width ~ hold
    net_photosynthesis: A_net ~ hold

    # Ball-Berry model parameters from Miner and Bauerle 2017, used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
    g0 => 0.017 ~ preserve(parameter)
    g1 => 4.53 ~ preserve(parameter)

    boundary_layer_conductance(width, wind=weather.wind): gb => begin
        # maize is an amphistomatous species, assume 1:1 (adaxial:abaxial) ratio.
        #sr = 1.0
        # switchgrass adaxial : abaxial (Awada 2002)
        # https://doi.org/10.4141/P01-031
        sr = 1.28
        ratio = (sr + 1)^2 / (sr^2 + 1)

        # characteristic dimension of a leaf, leaf width in m
        d = width * 0.72

        #1.42 # total BLC (both sides) for LI6400 leaf chamber
        1.4 * 0.147 * sqrt(max(0.1, wind) / d) * ratio
        # (1.4 * 1.1 * 6.62 * sqrt(wind / d) * (P_air / (R * (273.15 + T_air)))) # this is an alternative form including a multiplier for conversion from mm s-1 to mol m-2 s-1
        # 1.1 is the factor to convert from heat conductance to water vapor conductance, an avarage between still air and laminar flow (see Table 3.2, HG Jones 2014)
        # 6.62 is for laminar forced convection of air over flat plates on projected area basis
        # when all conversion is done for each surface it becomes close to 0.147 as given in Norman and Campbell
        # multiply by 1.4 for outdoor condition, Campbell and Norman (1998), p109, also see Jones 2014, pg 59 which suggest using 1.5 as this factor.
        # multiply by ratio to get the effective blc (per projected area basis), licor 6400 manual p 1-9
    end ~ track

    # stomatal conductance for water vapor in mol m-2 s-1
    # gamma: 10.0 for C4 maize
    #FIXME T_leaf not used
    stomatal_conductance(g0, g1, gb, m, A_net, CO2=weather.CO2, RH=weather.RH, gamma=10): gs => begin
        Cs = CO2 - (1.37 * A_net / gb) # surface CO2 in mole fraction
        Cs = max(Cs, gamma)

        a = m * g1 * A_net / Cs
        b = g0 + gb - (m * g1 * A_net / Cs)
        c = (-RH * gb) - g0
        #hs = scipy.optimize.brentq(lambda x: np.polyval([a, b, c], x), 0, 1)
        #hs = scipy.optimize.fsolve(lambda x: np.polyval([a, b, c], x), 0)
        #hs = roots(Poly([c, b, a])) |> maximum
        hs = quadratic_solve_upper(a, b, c)
        #hs = clamp(hs, 0.1, 1.0) # preventing bifurcation: used to be (0.3, 1.0) for C4 maize

        #FIXME unused?
        #T_leaf = l.temperature
        #es = w.vp.saturation(T=T_leaf)
        #Ds = (1 - hs) * es # VPD at leaf surface
        #Ds = w.vp.deficit(T=T_leaf, RH=hs)

        gs = g0 + (g1 * m * (A_net * hs / Cs))
        max(gs, g0)
    end ~ track #cycle(init=g0)

    leafp_effect(LWP=soil.WP_leaf, sf=2.3, phyf=-2.0): m => begin
        (1 + exp(sf * phyf)) / (1 + exp(sf * (phyf - LWP)))
    end ~ track

    total_conductance_h2o(gs, gb): gv => begin
        gs * gb / (gs + gb)
    end ~ track

    boundary_layer_resistance_co2(gb): rbc => begin
        1.37 / gb
    end ~ track

    stomatal_resistance_co2(gs): rsc => begin
        1.6 / gs
    end ~ track

    total_resistance_co2(rbc, rsc): rvc => begin
        rbc + rsc
    end ~ track
end

@system VaporPressure begin
    # Campbell and Norman (1998), p 41 Saturation vapor pressure in kPa
    a => 0.611 ~ preserve(parameter) # kPa
    b => 17.502 ~ preserve(parameter) # C
    c => 240.97 ~ preserve(parameter) # C

    saturation(a, b, c; T): es => a*exp((b*T)/(c+T)) ~ call
    ambient(es; T, RH): ea => es(T) * RH ~ call
    deficit(es; T, RH): vpd => es(T) * (1 - RH) ~ call
    relative_humidity(es; T, VPD): rh => 1 - VPD / es(T) ~ call

    # slope of the sat vapor pressure curve: first order derivative of Es with respect to T
    curve_slope(es, b, c; T, P): cs => es(T) * (b*c)/(c+T)^2 / P ~ call
end

#TODO: use improved @drive
#TODO: implement @unit
@system Weather begin
    vapor_pressure(context): vp => VaporPressure(; context=context) ~ ::VaporPressure

    PFD => 1500 ~ track # umol m-2 s-1
    CO2 => 400 ~ track # ppm
    RH => 0.6 ~ track # 0~1
    T_air => 25 ~ track # C
    wind => 2.0 ~ track # meters s-1
    P_air => 100 ~ track # kPa
    VPD(T_air, RH, vpd=vp.vpd) => vpd(T_air, RH) ~ track
    VPD_slope(T_air, P_air, cs=vp.cs) => cs(T_air, P_air) ~ track
end

import Base: show
show(io::IO, w::Weather) = print(io, "PFD = $(w.PFD), CO2 = $(w.CO2), RH = $(w.RH), T_air = $(w.T_air), wind = $(w.wind), P_air = $(w.P_air)")

@system Soil begin
    # pressure - leaf water potential MPa...
    WP_leaf => 0 ~ track
end

# C4 for maize, C3 for garlic
@system PhotosyntheticLeaf(Stomata, C4) begin
    weather ~ ::Weather(override)
    soil ~ ::Soil(override)

    #TODO organize leaf properties like water (LWP), nitrogen content?
    #TODO introduce a leaf geomtery class for leaf_width
    #TODO introduce a soil class for ET_supply

    ###########
    # Drivers #
    ###########

    # static properties
    nitrogen: N => 2.0 ~ preserve(parameter)

    # geometry
    width => 0.1 ~ preserve(parameter) # meters

    # soil?
    ET_supply: Jw => 0 ~ preserve(parameter)

    # dynamic properties

    # mesophyll CO2 partial pressure, ubar, one may use the same value as Ci assuming infinite mesohpyle conductance
    co2_atmosphere(CO2=weather.CO2, P_air=weather.P_air): Ca => (CO2 * P_air / 100) ~ track
    co2_mesophyll_upper_limit(Ca): Cmmax => 2Ca ~ track
    co2_mesophyll(Ca, A_net, rvc, P_air=weather.P_air, CO2=weather.CO2): [Cm, Ci] => begin
        P = P_air / 100
        Cm = Ca - A_net * rvc * P
        #println("+ Cm = $Cm, Ca = $Ca, A_net = $A_net, rvc = $rvc, P = $P")
    end ~ solve(lower=0, upper=Cmmax) # resolve(init=Ca)

    #FIXME is it right place? maybe need coordination with geometry object in the future
    light(PFD=weather.PFD): I2 => begin
        #FIXME make scatt global parameter?
        scatt = 0.15 # leaf reflectance + transmittance
        f = 0.15 # spectral correction

        Ia = PFD * (1 - scatt) # absorbed irradiance
        Ia * (1 - f) / 2 # useful light absorbed by PSII
    end ~ track

    gross_photosynthesis(A_net, Rd): A_gross => begin
        max(0, A_net + Rd) # gets negative when PFD = 0, Rd needs to be examined, 10/25/04, SK
    end ~ track

    temperature_adjustment(
        gb, gv, Jw,
        T_air=weather.T_air,
        PFD=weather.PFD,
        P_air=weather.P_air,
        VPD=weather.VPD,
        VPD_slope=weather.VPD_slope,
        # see Campbell and Norman (1998) pp 224-225
        # because Stefan-Boltzman constant is for unit surface area by denifition,
        # all terms including sbc are multilplied by 2 (i.e., gr, thermal radiation)
        lamda=44000, # KJ mole-1 at 25oC
        psc=6.66e-4,
        Cp=29.3, # thermodynamic psychrometer constant and specific heat of air (J mol-1 C-1)
        epsilon=0.97,
        sbc=5.6697e-8,
    ): T_adj => begin
        Tk = T_air + 273.15

        gha = gb * (0.135 / 0.147) # heat conductance, gha = 1.4*.135*sqrt(u/d), u is the wind speed in m/s} Mol m-2 s-1 ?
        gr = 4 * epsilon * sbc * Tk^3 / Cp * 2 # radiative conductance, 2 account for both sides
        ghr = gha + gr
        thermal_air = epsilon * sbc * Tk^4 * 2 # emitted thermal radiation
        psc1 = psc * ghr / gv # apparent psychrometer constant

        PAR = PFD / 4.55
        # If total solar radiation unavailable, assume NIR the same energy as PAR waveband
        NIR = PAR
        scatt = 0.15
        # shortwave radiation (PAR (=0.85) + NIR (=0.15) solar radiation absorptivity of leaves: =~ 0.5
        # times 2 for projected area basis
        R_abs = (1 - scatt)*PAR + scatt*NIR + 2*(epsilon * sbc * Tk^4)

        # debug dt I commented out the changes that yang made for leaf temperature for a test. I don't think they work
        if iszero(Jw)
            # eqn 14.6b linearized form using first order approximation of Taylor series
            (psc1 / (VPD_slope + psc1)) * ((R_abs - thermal_air) / (ghr * Cp) - VPD / (psc1 * P_air))
        else
            (R_abs - thermal_air - lamda * Jw) / (Cp * ghr)
        end
    end ~ solve(lower=-10, upper=10)

    temperature(T_adj, T_air=weather.T_air): T => begin
        T_leaf = T_air + T_adj
    end ~ track

    #TODO: expand @optimize decorator to support both cost function and variable definition
    # @temperature.optimize or minimize?
    # def temperature(self):
    #     (self.temperature - self.new_temperature)^2

    evapotranspiration(
        gv, T,
        T_air=weather.T_air,
        RH=weather.RH,
        P_air=weather.P_air,
        ambient=weather.vp.ambient,
        saturation=weather.vp.saturation
    ): ET => begin
        ea = ambient(T_air, RH)
        es_leaf = saturation(T)
        ET = gv * ((es_leaf - ea) / P_air) / (1 - (es_leaf + ea) / P_air)
        max(0, ET) # 04/27/2011 dt took out the 1000 everything is moles now
    end ~ track
end

#FIXME initialize weather and leaf more nicely, handling None case for properties
@system GasExchange begin
    #TODO: use externally initialized Weather / Soil
    weather(context): w => Weather(; context=context) ~ ::Weather
    soil(context) => Soil(; context=context) ~ ::Soil
    leaf(context, weather, soil) => PhotosyntheticLeaf(; context=context, weather=weather, soil=soil) ~ ::PhotosyntheticLeaf

    A_gross(x=leaf.A_gross) ~ track
    A_net(x=leaf.A_net) ~ track
    ET(x=leaf.ET) ~ track
    T_leaf(x=leaf.temperature) ~ track
    VPD(x=weather.VPD) ~ track #TODO: use Weather directly, instead of through PhotosyntheticLeaf
    gs(x=leaf.stomatal_conductance) ~ track
end

config = configure()

# config += """
# # Kim et al. (2007), Kim et al. (2006)
# # In von Cammerer (2000), Vpm25=120, Vcm25=60,Jm25=400
# # In Soo et al.(2006), under elevated C5O2, Vpm25=91.9, Vcm25=71.6, Jm25=354.2 YY
# C4.Vpmax.Vpm25 = 70
# C4.Vcmax.Vcm25 = 50
# C4.Jmax.Jm25 = 300
# C4.Rd.Rd25 = 2 # Values in Kim (2006) are for 31C, and the values here are normalized for 25C. SK
# """

# config += """
# [C4]
# # switgrass params from Albaugha et al. (2014)
# # https://doi.org/10.1016/j.agrformet.2014.02.013
# C4.Vpmax.Vpm25 = 52
# C4.Vcmax.Vcm25 = 26
# C4.Jmax.Jm25 = 145
# """

# config += """
# # switchgrass Vcmax from Le et al. (2010), others multiplied from Vcmax (x2, x5.5)
# C4.Vpmax.Vpm25 = 96
# C4.Vcmax.Vcm25 = 48
# C4.Jmax.Jm25 = 264
# """

# config += """
# C4.Vpmax.Vpm25 = 100
# C4.Vcmax.Vcm25 = 50
# C4.Jmax.Jm25 = 200
# """

# config += """
# C4.Vpmax.Vpm25 = 70
# C4.Vcmax.Vcm25 = 50
# C4.Jmax.Jm25 = 180.8
# """

# config += """
# # switchgrass params from Albaugha et al. (2014)
# C4.Rd.Rd25 = 3.6 # not sure if it was normalized to 25 C
# C4.Aj.theta = 0.79
# """

# config += """
# # In Sinclair and Horie, Crop Sciences, 1989
# C4.N_dep.s = 4
# C4.N_dep.N0 = 0.2
# # In J Vos et al. Field Crop Research, 2005
# C4.N_dep.s = 2.9
# C4.N_dep.N0 = 0.25
# # In Lindquist, Weed Science, 2001
# C4.N_dep.s = 3.689
# C4.N_dep.N0 = 0.5
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
# Stomata.m.sf = 2.3 # sensitivity parameter Tuzet et al. 2003 Yang
# Stomata.m.phyf = -1.2 # reference potential Tuzet et al. 2003 Yang
# """

# config += """
# #? = -1.68 # minimum sustainable leaf water potential (Albaugha 2014)
# # switchgrass params from Le et al. (2010)
# Stomata.m.sf = 6.5
# Stomata.m.phyf = -1.3
# """

# config += """
# #FIXME August-Roche-Magnus formula gives slightly different parameters
# # https://en.wikipedia.org/wiki/Clausius–Clapeyron_relation
# VaporPressure.a = 0.61094 # kPa
# VaporPressure.b = 17.625 # C
# VaporPressure.c = 243.04 # C
# """

@testset "photosynthesis" begin
    ge = instance(GasExchange; config=config)
    #write(transform(collect(ge)), tmp_path/"gasexchange.json")
end
