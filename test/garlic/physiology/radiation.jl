# Basic canopy architecture parameters, 10/10/00 S.Kim
# modified to represent heterogeneous canopies
# Uniform continuouse canopy: Width2 = 0
# Hedgerow canopy : Width1 = row width, Width2 = interrow, Height1 = hedge height, Height2 = 0
# Intercropping canopy: Height1, Width1, LA1 for Crop1, and so on
# Rose bent canopy: Height1=Upright canopy, Height2 = bent portion height, 10/16/02 S.Kim

# absorptance not explicitly considered here because it's a leaf characteristic not canopy
# Scattering is considered as canopy characteristics and reflectance is computed based on canopy scattering
# 08-20-12, SK

@enum LeafAngle begin
    spherical = 1
    horizontal = 2
    vertical = 3
    diaheliotropic = 4
    empirical = 5
    ellipsoidal = 6
end

#HACK not used
@enum Cover begin
    glass = 1
    acrylic = 2
    polyethyl = 3
    doublepoly = 4
    whitewashed = 5
    no_cover = 6
end

@enum WaveBand begin
    photosynthetically_active_radiation = 1
    near_infrared = 2
    longwave = 3
end

@system Radiation begin
    sun ~ ::Sun(override)
    LAI: leaf_area_index ~ track(override)

    leaf_angle => ellipsoidal ~ preserve::LeafAngle(parameter)

    # ratio of horizontal to vertical axis of an ellipsoid
    LAF: leaf_angle_factor => begin
        #1
        # leaf angle factor for corn leaves, Campbell and Norman (1998)
        #1.37
        # leaf angle factor for garlic canopy, from Rizzalli et al. (2002),  X factor in Campbell and Norman (1998)
        0.7
    end ~ preserve(parameter)

    wave_band => photosynthetically_active_radiation ~ preserve::WaveBand(parameter)

    # scattering coefficient (reflectance + transmittance)
    s: scattering => 0.15 ~ preserve(parameter)

    # clumping index
    clumping => 1.0 ~ preserve(parameter)

    #FIXME reflectance?
    #r_h => 0.05 ~ preserve(parameter)

    # Forward from Sun

    #TODO better name to make it drive?
    current_zenith_angle(sun.zenith_angle) ~ track(u"°")
    elevation_angle(sun.αs) ~ track(u"°")
    I0_dr(sun.PARdir): directional_photosynthetic_radiation ~ track(u"μmol/m^2/s" #= Quanta =#)
    I0_df(sun.PARdif): diffusive_photosynthetic_radiation ~ track(u"μmol/m^2/s" #= Quanta =#)

    # Leaf angle stuff?

    #TODO better name?
    leaf_angle_coeff(a=leaf_angle, leaf_angle_factor; zenith_angle(u"°")) => begin
        elevation_angle = 90u"°" - zenith_angle
        #FIXME need to prevent zero like sin_beta / cot_beta?
        α = elevation_angle
        t = zenith_angle
        # leaf angle distribution parameter
        x = leaf_angle_factor
        if a == spherical
            # When Lt accounts for total path length, division by sin(elev) isn't necessary
            1 / (2sin(α))
        elseif a == horizontal
            1.
        elseif a == vertical
            1 / (tan(α) * π/2)
        elseif a == empirical
            0.667
        elseif a == diaheliotropic
            1 / sin(α)
        elseif a == ellipsoidal
            sqrt(x^2 + tan(t)^2) / (x + 1.774 * (x+1.182)^-0.733)
        else
            1.
        end
    end ~ call

    #TODO make it @property if arg is not needed
    # Kb: Campbell, p 253, Ratio of projected area to hemi-surface area for an ellipsoid
    #TODO rename to extinction_coeff?
    # extinction coefficient assuming spherical leaf dist
    Kb_at(leaf_angle_coeff, clumping; zenith_angle(u"°")): projection_ratio_at => begin
        leaf_angle_coeff(zenith_angle) * clumping
    end ~ call

    Kb(Kb_at, current_zenith_angle): projection_ratio => begin
        Kb_at(current_zenith_angle)
    end ~ track

    # diffused light ratio to ambient, integrated over all incident angles from 0 to 90
    Kd_F(leaf_angle_coeff, LAI; a): diffused_fraction_for_Kd => begin
        c = leaf_angle_coeff(a)
        x = exp(-c * LAI)
        # Why multiplied by 2?
        2x * sin(a) * cos(a)
    end ~ integrate(from=0, to=π/2)

    # Kd: K for diffuse light, the same literature as above
    Kd(F=Kd_F, LAI, clumping): diffusion_ratio => begin
        K = -log(F) / LAI
        K * clumping
    end ~ track

    ###############################
    # de Pury and Farquhar (1997) #
    ###############################

    # Kb1: Kb prime in de Pury and Farquhar(1997)
    #TODO better name
    Kb1(Kb, s): projection_ratio_prime => (Kb * sqrt(1 - s)) ~ track

    # Kd1: Kd prime in de Pury and Farquhar(1997)
    #TODO better name
    Kd1(Kd, s): diffusion_ratio_prime => (Kd * sqrt(1 - s)) ~ track

    ################
    # Reflectivity #
    ################

    #TODO better name?
    reflectivity(rho_h, Kb, Kd) => begin
        rho_h * (2Kb / (Kb + Kd))
    end ~ track

    # canopy reflection coefficients for beam horizontal leaves, beam uniform leaves, and diffuse radiations

    # rho_h: canopy reflectance of beam irradiance on horizontal leaves, de Pury and Farquhar (1997)
    # also see Campbell and Norman (1998) p 255 for further info on potential problems
    rho_h(s): canopy_reflectivity_horizontal_leaf => begin
        (1 - sqrt(1 - s)) / (1 + sqrt(1 - s))
    end ~ track

    #TODO make consistent interface with siblings
    # rho_cb: canopy reflectance of beam irradiance for uniform leaf angle distribution, de Pury and Farquhar (1997)
    rho_cb_at(rho_h, Kb_at; zenith_angle): canopy_reflectivity_uniform_leaf_at => begin
        Kb = Kb_at(zenith_angle)
        1 - exp(-2rho_h * Kb / (1 + Kb))
    end ~ call

    rho_cb(rho_cb_at, current_zenith_angle): canopy_reflectivity_uniform_leaf => begin
        rho_cb_at(current_zenith_angle)
    end ~ track

    rho_cd_F(rho_cb_at; a): diffused_fraction_for_rho_cd => begin
        x = rho_cb_at(a)
        # Why multiplied by 2?
        2x * sin(a) * cos(a)
    end ~ integrate(from=0, to=π/2)

    # rho_cd: canopy reflectance of diffuse irradiance, de Pury and Farquhar (1997) Table A2
    rho_cd(I0_df, rho_cd_F): canopy_reflectivity_diffusion => begin
        # Probably the eqn A21 in de Pury is missing the integration terms of the angles??
        iszero(I0_df) ? 0. : rho_cd_F
    end ~ track

    # rho_soil: soil reflectivity for PAR band
    rho_soil: soil_reflectivity => 0.10 ~ preserve(parameter)

    #######################
    # I_l?: dePury (1997) #
    #######################

    # I_lb: dePury (1997) eqn A3
    I_lb(I0_dr, rho_cb, Kb1; L): irradiance_lb => begin
        I0_dr * (1 - rho_cb) * Kb1 * exp(-Kb1 * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_ld: dePury (1997) eqn A5
    I_ld(I0_df, rho_cb, Kd1; L): irradiance_ld => begin
        I0_df * (1 - rho_cb) * Kd1 * exp(-Kd1 * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_l: dePury (1997) eqn A5
    I_l(; L): irradiance_l => (I_lb(L) + I_ld(L)) ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_lbSun: dePury (1997) eqn A5
    I_lbSun(I0_dr, s, Kb, I_lSh; L): irradiance_l_sunlit => begin
        I_lb_sunlit = I0_dr * (1 - s) * Kb
        #TODO: check name I_lbSun vs. I_l_sunlit?
        I_l_sunlit = I_lb_sunlit + I_lSh(L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_lSh: dePury (1997) eqn A5
    I_lSh(I_ld, I_lbs; L): irradiance_l_shaded => begin
        I_ld(L) + I_lbs(L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_lbs: dePury (1997) eqn A5
    #FIXME: check name I_lbs vs. I_lbSun
    I_lbs(I0_dr, rho_cb, s, Kb1, Kb; L): irradiance_lbs => begin
        I0_dr * ((1 - rho_cb) * Kb1 * exp(-Kb1 * L) - (1 - s) * Kb * exp(-Kb * L))
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I0tot: total irradiance at the top of the canopy,
    # passed over from either observed PAR or TSolar or TIrradiance
    I0_tot(I0_dr, I0_df): irradiance_I0_tot => (I0_dr + I0_df) ~ track(u"μmol/m^2/s" #= Quanta =#)

    ########
    # I_c? #
    ########

    # I_tot, I_sun, I_shade: absorbed irradiance integrated over LAI per ground area
    #FIXME: not used, but seems producing very low values, need to check equations

    # I_c: Total irradiance absorbed by the canopy, de Pury and Farquhar (1997)
    I_c(rho_cb, I0_dr, I0_df, Kb1, Kd1, LAI): canopy_irradiance => begin
        #I_c = I_cSun + I_cSh
        I(I0, K) = (1 - rho_cb) * I0 * (1 - exp(-K * LAI))
        I_tot = I(I0_dr, Kb1) + I(I0_df, Kd1)
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # I_cSun: The irradiance absorbed by the sunlit fraction, de Pury and Farquhar (1997)
    # should this be the same os Qsl? 03/02/08 SK
    I_cSun(s, rho_cb, rho_cd, I0_dr, I0_df, Kb, Kb1, Kd1, LAI): canopy_sunlit_irradiance => begin
        I_c_sunlit = begin
            I0_dr * (1 - s) * (1 - exp(-Kb * LAI)) +
            I0_df * (1 - rho_cd) * (1 - exp(-(Kd1 + Kb) * LAI)) * Kd1 / (Kd1 + Kb) +
            I0_dr * ((1 - rho_cb) * (1 - exp(-(Kb1 + Kb) * LAI)) * Kb1 / (Kb1 + Kb) - (1 - s) * (1 - exp(-2Kb * LAI)) / 2)
        end
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # I_cSh: The irradiance absorbed by the shaded fraction, de Pury and Farquhar (1997)
    I_cSh(I_c, I_cSun): canopy_shaded_irradiance => (I_c - I_cSun) ~ track(u"μmol/m^2/s" #= Quanta =#)

    ######
    # Q? #
    ######

    # sunlit_photon_flux_density(_sunlit_Q) ~ track
    # shaded_photon_flux_density(_shaded_Q) ~ track

    # Qtot: total irradiance (dir + dif) at depth L, simple empirical approach
    Q_tot(I0_tot, s, Kb, Kd; L): irradiance_Q_tot => begin
        I0_tot * exp(-sqrt(1 - s) * ((Kb + Kd) / 2) * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # Qbt: total beam radiation at depth L
    Q_bt(I0_dr, s, Kb; L): irradiance_Q_bt => begin
        I0_dr * exp(-sqrt(1 - s) * Kb * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # net diffuse flux at depth of L within canopy
    Q_d(I0_dr, s, Kd; L): irradiance_Q_d => begin
        I0_df * exp(-sqrt(1 - s) * Kd * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # weighted average absorbed diffuse flux over depth of L within canopy
    # accounting for exponential decay, Campbell p261
    Q_dm(LAI, I0_df, s, Kd): irradiance_Q_dm => begin
        # Integral Qd / Integral L
        Q = I0_df * (1 - exp(-sqrt(1 - s) * Kd * LAI)) / (sqrt(1 - s) * Kd * LAI)
        isnan(Q) ? zero(Q) : Q
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # unintercepted beam (direct beam) flux at depth of L within canopy
    Q_b(I0_dr, Kb; L): irradiance_Q_b => begin
        I0_dr * exp(-Kb * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # mean flux density on sunlit leaves
    Q_sun(I0_dr, Kb, Q_sh): irradiance_Q_sunlit => begin
        I0_dr * Kb + Q_sh
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # flux density on sunlit leaves at depth L
    Q_sun_at(I0_dr, Kb; L): irradiance_Q_sunlit_at => begin
        I0_dr * Kb + Q_sh_at(L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # mean flux density on shaded leaves over LAI
    Q_sh(Q_dm, Q_scm): irradiance_Q_shaded => begin
        # It does not include soil reflection
        Q_dm + Q_scm
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # diffuse flux density on shaded leaves at depth L
    Q_sh_at(Q_d, Q_sc; L): irradiance_Q_shaded_at => begin
        # It does not include soil reflection
        Q_d(L) + Q_sc(L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # weighted average of Soil reflectance over canopy accounting for exponential decay
    Q_soilm(LAI, rho_soil, s, Kd, Q_soil): irradiance_Q_soilm => begin
        # Integral Qd / Integral L
        Q = Q_soil * rho_soil * (1 - exp(-sqrt(1 - s) * Kd * LAI)) / (sqrt(1 - s) * Kd * LAI)
        isnan(Q) ? zero(Q) : Q
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # weighted average scattered radiation within canopy
    Q_scm(LAI, I0_dr, s, Kb): irradiance_Q_scm => begin
        # total beam including scattered absorbed by canopy
        #FIXME should the last part be multiplied by LAI like others?
        #TODO simplify by using existing variables (i.e. Q_bt, Q_b)
        total_beam = I0_dr * (1 - exp(-sqrt(1 - s) * Kb * LAI)) / (sqrt(1 - s) * Kb)
        # non scattered beam absorbed by canopy
        nonscattered_beam = I0_dr * (1 - exp(-Kb * LAI)) / Kb
        Q = (total_beam - nonscattered_beam) / LAI
        # Campbell and Norman (1998) p 261, Average between top (where scattering is 0) and bottom.
        #(self.Q_bt(LAI) - Q_b(LAI)) / 2
        isnan(Q) ? zero(Q) : Q
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # scattered radiation at depth L in the canopy
    Q_sc(Q_bt, Q_b; L): irradiance_Q_sc => begin
        # total beam - nonscattered beam at depth L
        Q_bt(L) - Q_b(L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # total PFD at the soil surface under the canopy
    Q_soil(LAI, Q_tot): irradiance_Q_soil => Q_tot(LAI) ~ track(u"μmol/m^2/s" #= Quanta =#)

    ###################
    # Leaf Area Index #
    ###################

    sunrisen(elevation_angle, minimum_elevation_angle=5u"°") => begin
        elevation_angle > minimum_elevation_angle
    end ~ flag

    # sunlit LAI assuming closed canopy; thus not accurate for row or isolated canopy
    LAI_sunlit(sunrisen, Kb, LAI): sunlit_leaf_area_index => begin
        sunrisen ? (1 - exp(-Kb * LAI)) / Kb : 0.
    end ~ track

    # shaded LAI assuming closed canopy
    LAI_shaded(LAI, LAI_sunlit): shaded_leaf_area_index => begin
        LAI - LAI_sunlit
    end ~ track

    # sunlit fraction of current layer
    sunlit_fraction(sunrisen, Kb; L) => begin
        sunrisen ? exp(-Kb * L) : 0.
    end ~ call

    shaded_fraction(sunlit_fraction; L) => begin
        1 - sunlit_fraction(L)
    end ~ call
end
