using Polynomials

@system C4 begin
    #TODO: more robust interface to connect Systems (i.e. type check, automatic prop defines)
    leaf ~ ::System(override)

    co2_mesophyll(x="leaf.co2_mesophyll"): Cm => max(x, 0u"μmol/mol") ~ track(u"μmol/mol" #= CO2 =#)
    light(x="leaf.light"): I2 => max(x, 0u"μmol/m^2/s") ~ track(u"μmol/m^2/s" #= Quanta =#)
    temperature("leaf"): T ~ drive(u"°C")
    nitrogen("leaf"): N ~ drive

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

    gbs => 0.003 ~ preserve(u"mol/m^2/s" #= CO2 =#, parameter) # bundle sheath conductance to CO2, mol m-2 s-1
    # gi => 1.0 ~ preserve(parameter) # conductance to CO2 from intercelluar to mesophyle, mol m-2 s-1, assumed

    # Arrhenius equation
    temperature_dependence_rate(Ea, T, Tb=25u"°C"): T_dep => begin
        R = 8.314u"J/K/mol" # universal gas constant (J K-1 mol-1)
        #HACK handle too low temperature values during optimization
        Tk = max(T |> u"K", 0u"K")
        Tbk = max(Tb |> u"K", 0u"K")
        r = exp(Ea * (T - Tb) / (Tbk * R * Tk))
        #isinf(r) ? 0 : r
        r
    end ~ call

    nitrogen_limited_rate(N, s=2.9, N0=0.25): N_dep => begin
        2 / (1 + exp(-s * (max(N0, N) - N0))) - 1
    end ~ track

    # Rd25: Values in Kim (2006) are for 31C, and the values here are normalized for 25C. SK
    dark_respiration(T_dep, Rd25=2u"μmol/m^2/s" #= O2 =#, Ear=39800u"J/mol"): Rd => begin
        Rd25 * T_dep(Ear)
    end ~ track(u"μmol/m^2/s")

    Rm(Rd) => 0.5Rd ~ track(u"μmol/m^2/s")

    maximum_electron_transport_rate(
        T, T_dep, N_dep,
        Jm25=300u"μmol/m^2/s" #= Electron =#,
        Eaj=32800u"J/mol",
        Sj=702.6u"J/mol/K",
        Hj=220000u"J/mol"
    ): Jmax => begin
        R = 8.314u"J/K/mol"

        Tb = 25u"°C"
        Tk = T |> u"K"
        Tbk = Tb |> u"K"

        r = Jm25 * begin
            N_dep *
            T_dep(Eaj) *
            (1 + exp((Sj*Tbk - Hj) / (R*Tbk))) /
            (1 + exp((Sj*Tk  - Hj) / (R*Tk)))
        end
        max(0u"μmol/m^2/s", r)
    end ~ track(u"μmol/m^2/s" #= Electron =#)

    Om => begin
        # mesophyll O2 partial pressure
        O = 210 # gas units are mbar
    end ~ track(u"mbar", parameter)

    # Kp25: Michaelis constant for PEP caboxylase for CO2
    Kp(Kp25=80u"μbar") => begin
        Kp25 # T dependence yet to be determined
    end ~ track(u"μbar")

    # Kc25: Michaelis constant of rubisco for CO2 of C4 plants (2.5 times that of tobacco), ubar, Von Caemmerer 2000
    Kc(T_dep, Kc25=650u"μbar", Eac=59400u"J/mol") => begin
        Kc25 * T_dep(Eac)
    end ~ track(u"μbar")

    # Ko25: Michaelis constant of rubisco for O2 (2.5 times C3), mbar
    Ko(T_dep, Ko25=450u"mbar", Eao=36000u"J/mol") => begin
        Ko25 * T_dep(Eao)
    end ~ track(u"mbar")

    Km(Kc, Om, Ko) => begin
        # effective M-M constant for Kc in the presence of O2
        Kc * (1 + Om / Ko)
    end ~ track(u"μbar")

    Vpmax(N_dep, T_dep, Vpm25=70u"μmol/m^2/s" #= CO2 =#, EaVp=75100u"J/mol") => begin
        Vpm25 * N_dep * T_dep(EaVp)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    Vp(Vpmax, Cm, Kp) => begin
        # PEP carboxylation rate, that is the rate of C4 acid generation
        Vp = (Cm * Vpmax) / (Cm + (Kp / 1u"atm"))
        Vpr = 80u"μmol/m^2/s" #= CO2 =#  # PEP regeneration limited Vp, value adopted from vC book
        clamp(Vp, 0u"μmol/m^2/s", Vpr)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    # EaVc: Sage (2002) JXB
    Vcmax(N_dep, T_dep, Vcm25=50u"μmol/m^2/s" #= CO2 =#, EaVc=55900u"J/mol") => begin
        Vcm25 * N_dep * T_dep(EaVc)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    enzyme_limited_photosynthesis_rate(Vp, gbs, Cm, Rm, Vcmax, Rd): Ac => begin
        # Enzyme limited A (Rubisco or PEP carboxylation)
        Ac1 = Vp + gbs*Cm - Rm
        #Ac1 = max(0, Ac1) # prevent Ac1 from being negative Yang 9/26/06
        Ac2 = Vcmax - Rd
        #println("Ac1 = $Ac1, Ac2 = $Ac2")
        min(Ac1, Ac2)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    # Light and electron transport limited A mediated by J
    # theta: sharpness of transition from light limitation to light saturation
    # x: Partitioning factor of J, yield maximal J at this value
    transport_limited_photosynthesis_rate(T, Jmax, Rd, Rm, I2, gbs, Cm, theta=0.5, x=0.4): Aj => begin
        #FIXME: roots() requires no unit attached
        c, b, a = [I2*Jmax, -(I2+Jmax), theta]
        #a = a
        b = ustrip(u"μmol/m^2/s", b)
        c = ustrip(u"(μmol/m^2/s)^2", c)
        #J = roots(Poly([c, b, a])) |> minimum
        pr = roots(Poly([c, b, a]))
        J = minimum(pr) * u"μmol/m^2/s"
        #println("Jmax = $Jmax, J = $J")
        Aj1 = x * J/2 - Rm + gbs*Cm
        Aj2 = (1-x) * J/3 - Rd
        min(Aj1, Aj2)
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    net_photosynthesis(Ac, Aj, beta=0.99): A_net => begin
        # smooting the transition between Ac and Aj
        A_net = ((Ac+Aj) - ((Ac+Aj)^2 - 4beta*Ac*Aj)^0.5) / (2beta)
        #println("Ac = $Ac, Aj = $Aj, A_net = $A_net")
        A_net
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    #FIXME: currently not used variables

    # alpha: fraction of PSII activity in the bundle sheath cell, very low for NADP-ME types
    bundle_sheath_o2(A_net, gbs, Om, alpha=0.0001): Os => begin
        alpha * A_net / (0.047gbs) * 1u"atm" + Om # Bundle sheath O2 partial pressure, mbar
    end ~ track(u"mbar")

    bundle_sheath_co2(A_net, Vp, Cm, Rm, gbs): Cbs => begin
        p = Cm + (Vp - A_net - Rm) / gbs # Bundle sheath CO2 partial pressure, ubar
        #TODO: better way to handling conversion between ppm and ubar?
        p * 1u"atm"
    end ~ track(u"μbar")

    gamma(Rd, Km, Vcmax, Os, gamma1=0.193) => begin
        # half the reciprocal of rubisco specificity, to account for O2 dependence of CO2 comp point,
        # note that this become the same as that in C3 model when multiplied by [O2]
        gamma_star = gamma1 * Os
        (Rd*Km + Vcmax*gamma_star) / (Vcmax - Rd)
    end ~ track(u"μbar")
end

@system Stomata begin
    leaf ~ ::System(override)

    # Ball-Berry model parameters from Miner and Bauerle 2017, used to be 0.04 and 4.0, respectively (2018-09-04: KDY)
    g0 => 0.017 ~ track(u"mmol/m^2/s" #= H2O =#, parameter)
    g1 => 4.53 ~ track(parameter)

    A_net("leaf.A_net") ~ track(u"μmol/m^2/s" #= CO2 =#)
    CO2("leaf.weather.CO2") ~ track(u"μmol/mol")
    RH("leaf.weather.RH") ~ track(u"percent")

    diffusivity_ratio_boundary_layer: drb => 1.37 ~ preserve(#= u"H2O/CO2", =# parameter)
    diffusivity_ratio_air: dra => 1.6 ~ preserve(#= u"H2O/CO2", =# parameter)

    boundary_layer_conductance(width="leaf.width", wind="leaf.weather.wind"): gb => begin
        # maize is an amphistomatous species, assume 1:1 (adaxial:abaxial) ratio.
        #sr = 1.0
        # switchgrass adaxial : abaxial (Awada 2002)
        # https://doi.org/10.4141/P01-031
        sr = 1.28
        ratio = (sr + 1)^2 / (sr^2 + 1)

        # characteristic dimension of a leaf, leaf width in m
        d = 0.72width

        #FIXME: check units, remove ustrip
        #return 1.42 # total BLC (both sides) for LI6400 leaf chamber
        1.4 * 0.147 * ustrip(max(0.1u"m/s", wind) / d)^0.5 * ratio
        # (1.4 * 1.1 * 6.62 * (wind / d)^0.5 * (P_air / (R * (273.15 + T_air)))) # this is an alternative form including a multiplier for conversion from mm s-1 to mol m-2 s-1
        # 1.1 is the factor to convert from heat conductance to water vapor conductance, an avarage between still air and laminar flow (see Table 3.2, HG Jones 2014)
        # 6.62 is for laminar forced convection of air over flat plates on projected area basis
        # when all conversion is done for each surface it becomes close to 0.147 as given in Norman and Campbell
        # multiply by 1.4 for outdoor condition, Campbell and Norman (1998), p109, also see Jones 2014, pg 59 which suggest using 1.5 as this factor.
        # multiply by ratio to get the effective blc (per projected area basis), licor 6400 manual p 1-9
    end ~ track(u"mol/m^2/s" #= H2O =#)

    # stomatal conductance for water vapor in mol m-2 s-1
    # gamma: 10.0 for C4 maize
    #FIXME T_leaf not used
    stomatal_conductance(g0, g1, gb, m, A_net, CO2, RH, drb, gamma=10u"μmol/mol"): gs => begin
        Cs = CO2 - (drb * A_net / gb) # surface CO2 in mole fraction
        Cs = max(Cs, gamma)

        a = m * g1 * A_net / Cs
        b = g0 + gb - (m * g1 * A_net / Cs)
        c = (-RH * gb) - g0
        a = ustrip(u"mmol/m^2/s", a)
        b = ustrip(u"mmol/m^2/s", b)
        c = ustrip(u"mmol/m^2/s", c)
        #hs = scipy.optimize.brentq(lambda x: np.polyval([a, b, c], x), 0, 1)
        #hs = scipy.optimize.fsolve(lambda x: np.polyval([a, b, c], x), 0)
        #hs = roots(Poly([c, b, a]))) |> maximum
        pr = roots(Poly([c, b, a]))
        hss = filter(x -> 0 < x < 1, pr)
        hs = isempty(hss) ? 0.1 : maximum(hss)
        #FIXME: check unit
        hs = hs*u"mol/mol"
        #hs = clamp(hs, 0.1, 1.0) # preventing bifurcation: used to be (0.3, 1.0) for C4 maize

        #FIXME unused?
        #T_leaf = l.temperature
        #es = w.vp.saturation(T_leaf)
        #Ds = (1 - hs) * es # VPD at leaf surface
        #Ds = w.vp.deficit(T_leaf, hs)

        gs = g0 + (g1 * m * (A_net * hs / Cs))
        max(gs, g0)
    end ~ track(u"mol/m^2/s" #= H2O =#) #(init="g0")

    leafp_effect(LWP="leaf.soil.WP_leaf", sf=2.3u"MPa^-1", phyf=-2.0u"MPa"): m => begin
        (1 + exp(sf * phyf)) / (1 + exp(sf * (phyf - LWP)))
    end ~ track

    total_conductance_h2o(gs, gb): gv => begin
        gs * gb / (gs + gb)
    end ~ track(u"mmol/m^2/s" #= H2O =#)

    boundary_layer_resistance_co2(gb, drb): rbc => begin
        drb / gb
    end ~ track(u"m^2*s/mol")

    stomatal_resistance_co2(gs, dra): rsc => begin
        dra / gs
    end ~ track(u"m^2*s/mol")

    total_resistance_co2(rbc, rsc): rvc => begin
        rbc + rsc
    end ~ track(u"m^2*s/mol")
end

@system PhotosyntheticLeaf begin
    weather ~ ::System(override)
    soil ~ ::System(override)

    stomata => Stomata(; context=context, leaf=self) ~ ::System
    photosynthesis => C4(; context=context, leaf=self) ~ ::System # for maize
    #photosynthesis => C3(; context=context, leaf=self) ~ ::System # for garlic

    #TODO organize leaf properties like water (LWP), nitrogen content?
    #TODO introduce a leaf geomtery class for leaf_width
    #TODO introduce a soil class for ET_supply

    ###########
    # Drivers #
    ###########

    # static properties
    nitrogen => 2.0 ~ track(parameter)

    # geometry
    width => 10 // 100 ~ track(u"m", parameter)

    # soil?
    # actual water uptake rate (mol H2O m-2 s-1)
    ET_supply => 0 ~ track(u"mol/m^2/s" #= H2O =#, parameter)

    # dynamic properties

    # mesophyll CO2 partial pressure, ubar, one may use the same value as Ci assuming infinite mesohpyle conductance
    co2_mesophyll(A_net, P_air="weather.P_air", CO2="weather.CO2", rvc="stomata.rvc"): [Cm, Ci] => begin
        P = P_air / 100u"kPa"
        Ca = CO2 * P # conversion to partial pressure
        Cm = Ca - A_net * rvc * P
        #println("+ Cm = $Cm, Ca = $Ca, A_net = $A_net, rvc = $rvc, P = $P")
        clamp(Cm, 0, 2Ca)
        #Cm
    end ~ track(u"μmol/mol" #= CO2 =#)

    #FIXME is it right place? maybe need coordination with geometry object in the future
    light(PFD="weather.PFD"): I2 => begin
        #FIXME make scatt global parameter?
        scatt = 0.15 # leaf reflectance + transmittance
        f = 0.15 # spectral correction

        Ia = PFD * (1 - scatt) # absorbed irradiance
        Ia * (1 - f) / 2 # useful light absorbed by PSII
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    net_photosynthesis(A_net0="A_net", A_net1="photosynthesis.net_photosynthesis"): A_net => begin
        #I2 = light
        #println("A_net0 = $A_net0")
        #Cm0 = co2_mesophyll
        #Cm1 = co2_mesophyll(A_net1)
        #print("- I2 = $I2, Cm0 = $Cm0, T_leaf = $T_leaf, A_net0 = $A_net0, A_net1 = $A_net1, Cm1 = $Cm1")
        (A_net1 - A_net0)^2
    end ~ solve(u"μmol/m^2/s" #= CO2 =#)

    dark_respiration("photosynthesis.dark_respiration"): Rd ~ track(u"μmol/m^2/s" #= O2 =#)

    gross_photosynthesis(A_net, Rd): A_gross => begin
        max(0u"μmol/m^2/s", A_net + Rd) # gets negative when PFD = 0, Rd needs to be examined, 10/25/04, SK
    end ~ track(u"μmol/m^2/s" #= CO2 =#)

    stomatal_conductance("stomata.stomatal_conductance"): gs ~ track(u"μmol/m^2/s" #= H2O =#)

    temperature_adjustment(
        gb="stomata.boundary_layer_conductance",
        gv="stomata.total_conductance_h2o",
        T_air="weather.T_air",
        PFD="weather.PFD",
        P_air="weather.P_air",
        VPD="weather.VPD",
        VPD_slope="weather.VPD_slope",
        Jw="ET_supply",
        # see Campbell and Norman (1998) pp 224-225
        # because Stefan-Boltzman constant is for unit surface area by denifition,
        # all terms including sbc are multilplied by 2 (i.e., gr, thermal radiation)
        lamda=44u"kJ/mol", # KJ mole-1 at 25oC
        Cp=29.3u"J/mol/K", # thermodynamic psychrometer constant and specific heat of air (J mol-1 C-1)
        epsilon=0.97,
        sbc=5.6697e-8u"J/m^2/s/K^4", # Stefan-Boltzmann constant (W m-2 K-4)
    ): T_adj => begin
        Tk = T_air |> u"K"

        gha = gb * (0.135 / 0.147) # heat conductance, gha = 1.4*.135*sqrt(u/d), u is the wind speed in m/s} Mol m-2 s-1 ?
        gr = 4epsilon * sbc * Tk^3 / Cp * 2 # radiative conductance, 2 account for both sides
        ghr = gha + gr
        thermal_air = epsilon * sbc * Tk^4 * 2 # emitted thermal radiation
        psc = Cp / lamda # psychrometric constant (C-1) ~ 6.66e-4
        psc1 = psc * ghr / gv # apparent psychrometer constant

        PAR = (ustrip(PFD) / 4.55) * u"J/m^2/s" # W m-2
        # If total solar radiation unavailable, assume NIR the same energy as PAR waveband
        NIR = PAR
        scatt = 0.15
        # shortwave radiation (PAR (=0.85) + NIR (=0.15) solar radiation absorptivity of leaves: =~ 0.5
        # times 2 for projected area basis
        R_abs = (1 - scatt)*PAR + scatt*NIR + 2(epsilon * sbc * Tk^4)

        # debug dt I commented out the changes that yang made for leaf temperature for a test. I don't think they work
        if iszero(Jw)
            # eqn 14.6b linearized form using first order approximation of Taylor series
            (psc1 / (VPD_slope + psc1)) * ((R_abs - thermal_air) / (ghr * Cp) - VPD / (psc1 * P_air))
        else
            (R_abs - thermal_air - lamda * Jw) / (Cp * ghr)
        end
    end ~ track(u"K") #TODO: use solve

    temperature(T_adj, T_air="weather.T_air"): T => begin
        T_leaf = T_air + T_adj
    end ~ track(u"°C")

    #TODO: expand @optimize decorator to support both cost function and variable definition
    # @temperature.optimize or minimize?
    # def temperature(self):
    #     return (self.temperature - self.new_temperature)^2

    evapotranspiration(
        gv="stomata.total_conductance_h2o",
        T_air="weather.T_air",
        T="temperature",
        RH="weather.RH",
        P_air="weather.P_air",
        ambient="weather.vp.ambient",
        saturation="weather.vp.saturation"
    ): ET => begin
        ea = ambient(T_air, RH)
        es_leaf = saturation(T)
        ET = gv * ((es_leaf - ea) / P_air) / (1 - (es_leaf + ea) / P_air)
        max(0u"μmol/m^2/s", ET) # 04/27/2011 dt took out the 1000 everything is moles now
    end ~ track(u"μmol/m^2/s" #= H2O =#)
end

#FIXME initialize weather and leaf more nicely, handling None case for properties
@system GasExchange begin
    #TODO: use externally initialized Weather / Soil
    weather: w => Weather(; context=context) ~ ::Weather
    soil => Soil(; context=context) ~ ::Soil
    leaf => PhotosyntheticLeaf(; context=context, weather=self.weather, soil=self.soil) ~ ::PhotosyntheticLeaf

    A_gross("leaf.A_gross") ~ track(u"μmol/m^2/s" #= CO2 =#)
    A_net("leaf.A_net") ~ track(u"μmol/m^2/s" #= CO2 =#)
    ET("leaf.ET") ~ track(u"μmol/m^2/s" #= H2O =#)
    T_leaf("leaf.temperature") ~ track(u"°C")
    VPD("weather.VPD") ~ track(u"kPa") #TODO: use Weather directly, instead of through PhotosyntheticLeaf
    gs("leaf.stomata.stomatal_conductance") ~ track(u"mol/m^2/s" #= H2O =#)
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
