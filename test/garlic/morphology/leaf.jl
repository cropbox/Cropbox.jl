#TODO: rename *temperature to more genereral terms
@system LeafLengthTracker(BetaFunction) begin
    pheno: phenology ~ ::Phenology(override)
    T: temperature ~ ::int(override)
    #FIXME: leaves_potential is already max(leaves_generic, leaves_total)?
    n(np=pheno.leaves_potential, ng=pheno.leaves_generic): leaf_count => max(np, ng) ~ track
    Tn: minimum_temperature => 0 ~ preserve
    To(n): optimal_temperature => 0.88n ~ preserve
    Tx(n): maximum_temperature => 1.64n ~ preserve
end

@system LeafColdInjury begin
    T: temperature ~ hold

    _a: cold_injury_factor1 => -0.1 ~ preserve(u"K^-1", parameter)
    _b: cold_injury_factor2 => 1.6 ~ preserve(parameter)
    _Tc: cold_injury_critical_temperature => 0 ~ preserve(u"°C", parameter)

    CID(T, _Tc): cold_injury_duration => begin
        T < Tc ? 1 : -1
    end ~ accumulate(u"hr", min=0)

    "preliminary cold injury effect (2019-05-23: KDY)"
    ACIE(_a, _b, _Tc, T, CID): apparent_cold_injury_effect => begin
        a = T < Tc ? log(a * (T - Tc) + b) : 0
        1 - a / exp(1u"hr" / CID)
    end ~ track(min=0, max=1)

    _enable => true ~ flag(parameter)

    CIE(CIE, ACIE, CID): cold_injury_effect => begin
        iszero(CID) ? 1 : min(CIE, ACIE)
    end ~ track(init=1, when=_enable)
end

@system Leaf(Organ, LeafColdInjury) begin
    rank ~ ::int(override) # preserve

    # cm dd-1 Fournier and Andrieu 1998 Pg239.
    # This is the "potential" elongation rate with no water stress Yang
    # elongation_rate => 0.564 ~ preserve(u"cm/d", parameter)

    # max elongation rate (cm per day) at optimal temperature
    # (Topt: 31C with Tbase = 9.8C using 0.564 cm/dd rate from Fournier 1998 paper above
    LER_max: maximum_elongation_rate => 12 ~ preserve(u"cm/d", parameter)

    LM_min: minimum_length_of_longest_leaf => 60 ~ preserve(u"cm", parameter)

    # leaf lamina width to length ratio
    length_to_width_ratio => begin
        #0.106 # for maize
        0.05 # for garlic
    end ~ preserve(parameter)

    # leaf area coeff with respect to L*W (A_LW)
    area_ratio => 0.75 ~ preserve(parameter)

    # staygreen trait of the hybrid
    # stay green for this value times growth period after peaking before senescence begins
    # An analogy for this is that with no other stresses involved,
    # it takes 15 years to grow up, stays active for 60 years,
    # and age the last 15 year if it were for a 90 year life span creature.
    # Once fully grown, the clock works differently so that the hotter it is quicker it ages
    SG: stay_green => 3.5 ~ preserve(parameter)

    maximum_aging_rate(LER_max) => LER_max ~ track(u"cm/d")

    #############
    # Variables #
    #############

    #FIXME
    potential_leaves(pheno.leaves_potential) ~ track

    #FIXME
    extra_leaves(np=potential_leaves, ng=pheno.leaves_generic) => (np - ng) ~ track

    k: maximum_length_of_longest_leaf_adjustment => begin
        # no length adjustment necessary for garlic, unlike MAIZE (KY, 2016-10-12)
        # 24.0
        0
    end ~ preserve(u"cm^2", parameter)

    maximum_length(LM_min, extra_leaves, k): maximum_length_of_longest_leaf => begin
        sqrt(LM_min^2 + k * extra_leaves)
    end ~ track(u"cm")

    maximum_width(l=maximum_length, r=length_to_width_ratio) => begin
        # Fournier and Andrieu(1998) Pg242 YY
        l * r
    end ~ track(u"cm")

    maximum_area(l=maximum_length, w=maximum_width, r=area_ratio) => begin
        # daughtry and hollinger (1984) Fournier and Andrieu(1998) Pg242 YY
        l * w * r
    end ~ track(u"cm^2")

    area_from_length(; L(u"cm")) => begin
        #HACK ensure zero area for zero length
        # for garlic, see JH's thesis
        l = Cropbox.deunitfy(L)
        iszero(l) ? l : 0.639945 + 0.954957l + 0.005920l^2
    end ~ call(u"cm^2")

    area_increase_from_length(length) => begin
        # for garlic, see JH's thesis
        l = Cropbox.deunitfy(length)
        0.954957 + 2*0.005920l
    end ~ track(u"cm^2")

    #TODO better name, shared by growth_duration and potential_area
    #TODO should be a plant parameter not leaf (?)
    rank_effect(rank, n=potential_leaves, weight=1) => begin
        n_m = 5.93 + 0.33n # the rank of the largest leaf. YY
        a = (-10.61 + 0.25n) * weight
        b = (-5.99 + 0.27n) * weight
        # equation 7 in Fournier and Andrieu (1998). YY

        # equa 8(b)(Actually eqn 6? - eqn 8 deals with leaf age - DT)
        # in Fournier and Andrieu(1998). YY
        scale = rank / n_m - 1
        exp(a * scale^2 + b * scale^3)
    end ~ track

    potential_length_tracker(context, pheno, temperature=rank) ~ ::LeafLengthTracker
    potential_length(maximum_length, β=potential_length_tracker.ΔT) => begin
        # for MAIZSIM
        #self.maximum_length * self.rank_effect(weight=0.5)
        # for beta fn calibrated from JH's thesis for SP and KM varieties, 8/10/15, SK
        maximum_length * β
    end ~ track(u"cm")

    # from CLeaf::calc_dimensions()
    # LM_min is a length characteristic of the longest leaf,in Fournier and Andrieu 1998, it was 90 cm
    # LA_max is a fn of leaf no (Birch et al, 1998 fig 4) with largest reported value near 1000cm2. This is implemented as lfno_effect below, SK
    # LM_min of 115cm gives LA of largest leaf 1050cm2 when totalLeaves are 25 and Nt=Ng, SK 1-20-12
    # Without lfno_effect, it can be set to 97cm for the largest leaf area to be at 750 cm2 with Nt ~= Ng (Lmax*Wmax*0.75) based on Muchow, Sinclair, & Bennet (1990), SK 1-18-2012
    # Eventually, this needs to be a cultivar parameter and included in input file, SK 1-18-12
    # the unit of k is cm^2 (Fournier and Andrieu 1998 Pg239). YY
    # L_max is the length of the largest leaf when grown at T_peak. Here we assume LM_min is determined at growing Topt with minmal (generic) leaf no, SK 8/2011
    # If this routine runs before TI, totalLeaves = genericLeafNo, and needs to be run with each update until TI and total leaves are finalized, SK
    GD(potential_length, LER_max): growth_duration => begin
        # shortest possible linear phase duration in physiological time (days instead of GDD) modified
        days = potential_length / LER_max
        # for garlic
        1.5days
    end ~ track(u"d")

    phase1_delay(rank) => begin
        # not used in MAIZSIM because LTAR is used to initiate leaf growth.
        # Fournier's value : -5.16+1.94*rank;equa 11 Fournier and Andrieu(1998) YY, This is in plastochron unit
        -5.16 + 1.94rank
    end ~ track(min=0)

    leaf_number_effect(potential_leaves) => begin
        # Fig 4 of Birch et al. (1998)
        exp(-1.17 + 0.047potential_leaves)
    end ~ track(min=0.5, max=1.0)

    potential_area(potential_length, area_from_length) => begin
        # for MAIZSIM
        # equa 6. Fournier and Andrieu(1998) multiplied by Birch et al. (1998) leaf no effect
        # LA_max the area of the largest leaf
        # PotentialArea potential final area of a leaf with rank "n". YY
        #self.maximum_area * self.leaf_number_effect * self.rank_effect(weight=1)
        # for garlic
        area_from_length(potential_length)
    end ~ track(u"cm^2")

    green_ratio(senescence_ratio) => (1 - senescence_ratio) ~ track

    green_area(green_ratio, area) => (green_ratio * area) ~ track(u"cm^2")

    #TODO implement Parent and Tardieu (2011, 2012) approach for leaf elongation in response to T and VPD, and normalized at 20C, SK, Nov 2012
    # elongAge indicates where it is now along the elongation stage or duration.
    # duration is determined by totallengh/maxElongRate which gives the shortest duration to reach full elongation in the unit of days.
    elongation_age(pheno.BF.ΔT) ~ accumulate(when=growing, u"d")

    #TODO move to common module (i.e. Organ?)
    beta_growth(t_b=0u"d", delta=1; t(u"d"), t_e(u"d"), c_m(u"cm/d")) => begin
        t = clamp(t, zero(t), t_e)
        t_m = t_e / 2 #TODO: allow custom value again?
        t_et = t_e - t
        t_em = t_e - t_m
        t_tb = t - t_b
        t_mb = t_m - t_b
        c_m * ((t_et / t_em) * (t_tb / t_mb)^(t_mb / t_em))^delta
    end ~ call(u"cm/d")

    potential_elongation_rate(beta_growth, elongation_age, LER_max, GD) => begin
        #TODO proper integration with scipy.integrate?
        beta_growth(elongation_age, GD, LER_max)
    end ~ track(when=growing, u"cm/d")

    #TODO: incorporate stress effects
    actual_elongation_rate(potential_elongation_rate, cold_injury_effect) => begin
        potential_elongation_rate * cold_injury_effect
    end ~ track(u"cm/d")

    temperature_effect_func(; T_grow(u"°C"), T_peak(u"°C"), T_base(u"°C")) => begin
        # T_peak is the optimal growth temperature at which the potential leaf size determined in calc_mophology achieved.
        # Similar concept to fig 3 of Fournier and Andreiu (1998)

        # phyllochron corresponds to PHY in Lizaso (2003)
        # phyllochron needed for next leaf appearance in degree days (GDD8) - 08/16/11, SK.
        #phyllochron = (dv->get_T_Opt()- Tb)/(dv->get_Rmax_LTAR());

        T_ratio = (T_grow - T_base) / (T_peak - T_base)
        # final leaf size is adjusted by growth temperature determining cell size during elongation
        max(T_ratio * exp(1 - T_ratio), zero(T_ratio))
    end ~ call

    temperature_effect => begin
        #temperature_effect_func(self.p.pheno.growing_temperature, 18.7, 8.0) # for MAIZSIM
        #FIXME garlic model uses current temperature, not average growing temperature
        #temperature_effect_func(self.p.pheno.temperature, self.p.pheno.optimal_temperature, 0) # for garlic
        #FIXME garlic model does not actually use temperature effect on final leaf size calculation
        1.0 # for garlic
    end ~ track

    potential_expansion_rate(t=elongation_age, t_e=GD, w_max=potential_area) => begin
        # t_e = 1.5 * w_max / c_m
        t = min(t, t_e)
        #FIXME can we introduce new w_max here when w_max in t_e (growth duration) supposed to be potential length?
        # c_m from Eq. 9, r (= dw/dt / c_m) from Eq. 7 of Yin (2003)
        #HACK can be more simplified
        #c_m = 1.5 / t_e * w_max
        #r = 4t * (t_e - t) / t_e^2
        t_m = t_e / 2
        c_m = (2t_e - t_m) / (t_e * (t_e - t_m)) * (t_m / t_e)^(t_m / (t_e - t_m)) * w_max
        r = (t_e - t) / (t_e - t_m) * (t / t_m)^(t_m / (t_e - t_m))
        #FIXME dt here is physiological time, whereas timestep multiplied in potential_area_increase is chronological time
        c_m * r # dw/dt
    end ~ track(u"cm^2/d")

    potential_area_increase(area_from_length, length, actual_length_increase, area) => begin
        ##area = max(0, water_effect * T_effect * self.potential_area * (1 + (t_e - self.elongation_age) / (t_e - t_m)) * (self.elongation_age / t_e)**(t_e / (t_e - t_m)))
        #maximum_expansion_rate = T_effect * self.potential_area * (2*t_e - t_m) / (t_e * (t_e - t_m)) * (t_m / t_e)**(t_m / (t_e - t_m))
        # potential leaf area increase without any limitations
        #max(0, maximum_expansion_rate * max(0, (t_e - self.elongation_age) / (t_e - t_m) * (self.elongation_age / t_m)**(t_m / (t_e - t_m))) * self.timestep)
        # for MAIZSIM
        #self.potential_expansion_rate * self.timestep
        # for garlic
        #TODO need common framework dealing with derivatives
        #area_increase_from_length(actual_length_increase)
        area_from_length(length + actual_length_increase) - area
    end ~ track(when=growing, u"cm^2")

    # create a function which simulates the reducing in leaf expansion rate
    # when predawn leaf water potential decreases. Parameterization of rf_psil
    # and rf_sensitivity are done with the data from Boyer (1970) and Tanguilig et al (1987) YY
    #FIXME: unit of call args kPa?
    water_potential_effect_func(; psi_predawn, psi_th) => begin
        #psi_predawn = self.p.soil.WP_leaf_predawn
        # psi_th: threshold wp below which stress effect shows up

        # DT Oct 10, 2012 changed this so it was not as sensitive to stress near -0.5 lwp
        # SK Sept 16, 2014 recalibrated/rescaled parameter estimates in Yang's paper. The scale of Boyer data wasn't set correctly
        # sensitivity = 1.92, LeafWPhalf = -1.86, the sensitivity parameter may be raised by 0.3 to 0.5 to make it less sensitivity at high LWP, SK
        s_f = 0.4258 # 0.5
        psi_f = -1.4251 # -1.0
        e = (1 + exp(s_f * psi_f)) / (1 + exp(s_f * (psi_f - (psi_predawn - psi_th))))
        min(e, 1)
    end ~ call

    water_potential_effect(; threshold) => begin
        # for MAIZSIM
        #water_potential_effect_func(soil.WP_leaf_predawn, threshold)
        # for garlic
        1.0
    end ~ call

    carbon_effect => 1.0 ~ track

    length(actual_elongation_rate) ~ accumulate(u"cm", time=elongation_age, timeunit=u"d")
    actual_length_increase(actual_elongation_rate) ~ capture(u"cm", time=elongation_age, timeunit=u"d")

    # actual area
    area(water_potential_effect, carbon_effect, temperature_effect, area_from_length, length) => begin
        # See Kim et al. (2012) Agro J. for more information on how this relationship has been determined based on multiple studies and is applicable across environments
        #FIXME: unit of threshold kPa?
        we = water_potential_effect(-0.8657)

        # place holder
        ce = carbon_effect
        te = temperature_effect

        # growth temperature effect is now included here, outside of potential area increase calculation
        #TODO water and carbon effects are not multiplicative?
        min(we, ce) * te * area_from_length(length)
    end ~ track(u"cm^2")

    #TODO remove if unnecessary
    # @property
    # def actual_area_increase(self):
    #     #FIXME area increase tracking should be done by some global state tracking manager
    #     raise NotImplementedError("actual_area_increase")
    #
    # @property
    # def relative_area_increase(self):
    #     #HACK meaning changed from 'relative to other leaves' (spatial) to 'relative to previous state' (temporal)
    #     # adapted from CPlant::calcPerLeafRelativeAreaIncrease()
    #     #self.potential_area_increase / self.nodal_unit.plant.area.potential_leaf_increase
    #     da = self.actual_area_increase
    #     a = self.area - da
    #     if a > 0:
    #         da / a
    #     else:
    #         0

    stay_green_water_stress_duration(water_potential_effect, scale=0.5, threshold=-4.0) => begin
        # One day of cumulative severe water stress (i.e., water_effect = 0.0 around -4MPa) would result in a reduction of leaf lifespan in relation staygreeness and growthDuration, SK
        # if scale is 1.0, one day of severe water stress shortens one day of stayGreenDuration
        #TODO remove WaterStress and use general Accumulator with a lambda function?
        scale * (1 - water_potential_effect(threshold))
    end ~ accumulate(when=mature, u"d")

    stay_green_duration(SG, GD, stay_green_water_stress_duration) => begin
        # SK 8/20/10: as in Sinclair and Horie, 1989 Crop sciences, N availability index scaled between 0 and 1 based on
        #nitrogen_index = max(0, (2 / (1 + exp(-2.9 * (self.g_content - 0.25))) - 1))
        SG * GD - stay_green_water_stress_duration
    end ~ track(u"d", min=0)

    # Assumes physiological time for senescence is the same as that for growth though this may be adjusted by stayGreen trait
    # a peaked fn like beta fn not used here because aging should accelerate with increasing T not slowing down at very high T like growth,
    # instead a q10 fn normalized to be 1 at T_opt is used, this means above Top aging accelerates.
    active_age(pheno.Q10.ΔT) ~ accumulate(when=mature & !aging, u"d")

    senescence_water_stress_duration(water_potential_effect, scale=0.5, threshold=-4.0) => begin
        # if scale is 0.5, one day of severe water stress at predawn shortens one half day of agingDuration
        scale * (1 - water_potential_effect(threshold))
    end ~ accumulate(when=aging, u"d")

    senescence_duration(GD, senescence_water_stress_duration) => begin
        # end of growth period, time to maturity
        GD - senescence_water_stress_duration
    end ~ track(u"d", min=0)

    #TODO active_age and senescence_age could share a tracker with separate intervals
    #TODO support clipping with @rate option or sub-decorator (i.e. @active_age.clip)
    senescence_age(pheno.Q10.ΔT) ~ accumulate(when=aging & !dead, u"d")

    #TODO confirm if it really means the senescence ratio, not rate
    senescence_ratio(maximum_aging_rate, senescence_age, length) => begin
        # for MAIZSIM
        # t = self.senescence_age
        # t_e = self.senescence_duration
        # if t >= t_e:
        #     1
        # else:
        #     t_m = t_e / 2
        #     r = (1 + (t_e - t) / (t_e - t_m)) * (t / t_e)**(t_e / (t_e - t_m))
        #     clip(r, 0., 1.)
        # for garlic
        if iszero(length)
            0
        else
            maximum_aging_rate * senescence_age / length
        end
    end ~ track(min=0, max=1)

    senescent_area(senescence_ratio, area) => begin
        # Leaf senescence accelerates with drought and heat. see http://www.agry.purdue.edu/ext/corn/news/timeless/TopLeafDeath.html
        # rate = self._growth_rate(self.senescence_age, self.senescence_duration)
        # rate * self.timestep * self.area
        senescence_ratio * area
    end ~ track(u"cm^2")

    SLA(area, mass): specific_leaf_area => begin
        # temporary for now - it should vary by age. Value comes from some of Soo's work
        #200.0
        area / mass
    end ~ track(u"cm^2/g")

    # Maturity

    #HACK: tracking should happen after plant emergence (due to implementation of original beginFromEmergence)
    maturity(pheno.GD.r) ~ accumulate(when=pheno.emerged & !mature, u"K")

    # Nitrogen

    #FIXME avoid incorrect cycle detection (nitrogen member vs. module) - ?
    N: nitrogen => begin
        #TODO is this default value needed?
        # no N stress
        3.0
        #TODO remove self.p.* referencing
        #FIXME enable Nitrogen trait
        #self.p.nitrogen.leaf_content
    end ~ track

    ##########
    # States #
    ##########

    initiated => begin
        # no explicit initialize() here
        true
    end ~ flag

    appeared(rank, l=pheno.leaves_appeared) => (rank <= l) ~ flag

    growing(appeared, mature) => (appeared && !mature) ~ flag

    mature(elongation_age, GD, area, potential_area) => begin
        elongation_age >= GD || area >= potential_area
    end ~ flag

    aging(mature, physiological_age, SG, maturity) => begin
        # for MAIZSIM
        #active_age >= stay_green_duration
        # for garlic
        mature && physiological_age > SG * maturity
    end ~ flag

    dead(senescence_ratio) => begin
        #senescent_area >= area
        senescence_ratio >= 1
        #senescence_age >= senescence_duration?
    end ~ flag

    dropped(mature, dead) => (mature && dead) ~ flag
end
