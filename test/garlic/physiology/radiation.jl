# Basic canopy architecture parameters, 10/10/00 S.Kim
# modified to represent heterogeneous canopies
# Uniform continuouse canopy: Width2 = 0
# Hedgerow canopy : Width1 = row width, Width2 = interrow, Height1 = hedge height, Height2 = 0
# Intercropping canopy: Height1, Width1, LA1 for Crop1, and so on
# Rose bent canopy: Height1=Upright canopy, Height2 = bent portion height, 10/16/02 S.Kim

# abscissas
const GAUSS3 = [-0.774597, 0, 0.774597]
const WEIGHT3 = [0.555556 0.888889 0.555556]

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
    photothetically_active_radiation = 1
    near_infrared = 2
    longwave = 3
end

@system Radiation begin
    sun ~ ::Sun(override)

    # to access cumulative LAI at the layer
    development ~ ::Development(override)
    leaf_area_index(development): LAI ~ drive(u"cm^2/m^2")

    leaf_angle => ellipsoidal ~ preserve(parameter)

    # ratio of horizontal to vertical axis of an ellipsoid
    leaf_angle_factor: LAF => begin
        #1
        # leaf angle factor for corn leaves, Campbell and Norman (1998)
        #1.37
        # leaf angle factor for garlic canopy, from Rizzalli et al. (2002),  X factor in Campbell and Norman (1998)
        0.7
    end ~ preserve(parameter)

    wave_band => photothetically_active_radiation ~ preserve(parameter)

    # scattering coefficient (reflectance + transmittance)
    scattering: s => 0.15 ~ preserve(parameter)

    # clumping index
    clumping => 1 ~ preserve(parameter)

    #FIXME reflectance?
    #r_h => 0.05 ~ preserve(parameter)

    # Forward from Sun

    #TODO better name to make it drive?
    current_zenith_angle(x=sun.zenith_angle) ~ track(u"°")
    elevation_angle(sun) ~ drive(u"°")
    directional_photosynthetic_radiation(sun): I0_dr ~ drive(u"μmol/m^2/s" #= Quanta =#)
    diffusive_photosynthetic_radiation(sun): I0_df ~ drive(u"μmol/m^2/s" #= Quanta =#)

    # Leaf angle stuff?

    #TODO better name?
    leaf_angle_coeff(leaf_angle, leaf_angle_factor; zenith_angle) => begin
        elevation_angle = 90u"°" - zenith_angle
        #FIXME need to prevent zero like sin_beta / cot_beta?
        a = elevation_angle
        t = zenith_angle
        # leaf angle distribution parameter
        x = leaf_angle_factor
        Dict(
            # When Lt accounts for total path length, division by sin(elev) isn't necessary
            spherical => 1 / (2sin(a)),
            horizontal => 1,
            vertical => 1 / (tan(a) * π/2),
            empirical => 0.667,
            diaheliotropic => 1 / sin(a),
            ellipsoidal => sqrt(x^2 + tan(t)^2) / (x + 1.774 * (x+1.182)^-0.733),
        )[leaf_angle]
    end ~ call

    #TODO make it @property if arg is not needed
    # Kb: Campbell, p 253, Ratio of projected area to hemi-surface area for an ellisoid
    #TODO rename to extinction_coeff?
    # extiction coefficient assuming spherical leaf dist
    projection_ratio_at(leaf_angle_coeff, clumping; zenith_angle): Kb_at => begin
        leaf_angle_coeff(zenith_angle=zenith_angle) * clumping
    end ~ call

    projection_ratio(Kb_at, current_zenith_angle): Kb => begin
        Kb_at(zenith_angle=current_zenith_angle)
    end ~ track

    # diffused light ratio to ambient, itegrated over all incident angles from -90 to 90
    angles => [π/4 * (g+1) for g in GAUSS3] ~ preserve(u"rad", static)

    diffused_fraction(a=angles; x): fdf => begin
        # Why multiplied by 2?
        df = WEIGHT3 * ((π/4) * (2x .* sin.(a) .* cos.(a)))
        #FIXME better way to handling 1-element array value?
        df[1]
    end ~ call

    # Kd: K for diffuse light, the same literature as above
    diffusion_ratio(LAI, angles, leaf_angle_coeff, fdf, clumping): Kd => begin
        coeffs = [leaf_angle_coeff(zenith_angle=a) for a in angles]
        F = fdf(x=exp.(-coeffs * LAI))
        K = -log(F) / LAI
        K * clumping
    end ~ track

    ##############################
    # dePury and Farquhar (1997) #
    ##############################

    # Kb1: Kb prime in de Pury and Farquhar(1997)
    #TODO better name
    projection_ratio_prime(Kb, s): Kb1 => (Kb * sqrt(1 - s)) ~ track

    # Kd1: Kd prime in de Pury and Farquhar(1997)
    #TODO better name
    diffusion_ratio_prime(Kd, s): Kd1 => (Kd * sqrt(1 - s)) ~ track

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
    canopy_reflectivity_horizontal_leaf(s): rho_h => begin
        (1 - sqrt(1 - s)) / (1 + sqrt(1 - s))
    end ~ track

    #TODO make consistent interface with siblings
    # rho_cb: canopy reflectance of beam irradiance for uniform leaf angle distribution, de Pury and Farquhar (1997)
    canopy_reflectivity_uniform_leaf_at(rho_h, Kb_at; zenith_angle): rho_cb_at => begin
        Kb = Kb_at(zenith_angle=zenith_angle)
        1 - exp(-2rho_h * Kb / (1 + Kb))
    end ~ call

    canopy_reflectivity_uniform_leaf(rho_cb_at, current_zenith_angle): rho_cb => begin
        rho_cb_at(zenith_angle=current_zenith_angle)
    end ~ track

    # rho_cd: canopy reflectance of diffuse irradiance, de Pury and Farquhar (1997) Table A2
    canopy_reflectivity_diffusion(I0_df, angles, rho_cb_at, fdf): rho_cd => begin
        # Probably the eqn A21 in de Pury is missing the integration terms of the angles??
        iszero(I0_df) ? 0. : fdf(x=[rho_cb_at(zenith_angle=a) for a in angles])
    end ~ track

    # rho_soil: soil reflectivity for PAR band
    soil_reflectivity: rho_soil => 0.10 ~ preserve(parameter)

    #######################
    # I_l?: dePury (1997) #
    #######################

    # I_lb: dePury (1997) eqn A3
    irradiance_lb(I0_dr, rho_cb, Kb1; L): I_lb => begin
        I0_dr * (1 - rho_cb) * Kb1 * exp(-Kb1 * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_ld: dePury (1997) eqn A5
    irradiance_ld(I0_df, rho_cb, Kd1; L): I_ld => begin
        I0_df * (1 - rho_cb) * Kd1 * exp(-Kd1 * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_l: dePury (1997) eqn A5
    irradiance_l(; L): I_l => (I_lb(L=L) + I_ld(L=L)) ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_lbSun: dePury (1997) eqn A5
    irradiance_l_sunlit(I0_dr, s, Kb, I_lSh; L): I_lbSun => begin
        I_lb_sunlit = I0_dr * (1 - s) * Kb
        #TODO: check name I_lbSun vs. I_l_sunlit?
        I_l_sunlit = I_lb_sunlit + I_lSh(L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_lSh: dePury (1997) eqn A5
    irradiance_l_shaded(I_ld, I_lbs; L): I_lSh => begin
        I_ld(L=L) + I_lbs(L=L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I_lbs: dePury (1997) eqn A5
    #FIXME: check name I_lbs vs. I_lbSun
    irradiance_lbs(I0_dr, rho_cb, s, Kb1, Kb; L): I_lbs => begin
        I0_dr * ((1 - rho_cb) * Kb1 * exp(-Kb1 * L) - (1 - s) * Kb * exp(-Kb * L))
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # I0tot: total irradiance at the top of the canopy,
    # passed over from either observed PAR or TSolar or TIrradiance
    irradiance_I0_tot(I0_dr, I0_df): I0_tot => (I0_dr + I0_df) ~ track(u"μmol/m^2/s" #= Quanta =#)

    ########
    # I_c? #
    ########

    # I_tot, I_sun, I_shade: absorved irradiance integrated over LAI per ground area
    #FIXME: not used, but seems producing very low values, need to check equations

    # I_c: Total irradiance absorbed by the canopy, de Pury and Farquhar (1997)
    canopy_irradiance(rho_cb, I0_dr, I0_df, Kb1, Kd1, LAI): I_c => begin
        #I_c = I_cSun + I_cSh
        I(I0, K) = (1 - rho_cb) * I0 * (1 - exp(-K * LAI))
        I_tot = I(I0_dr, Kb1) + I(I0_df, Kd1)
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # I_cSun: The irradiance absorbed by the sunlit fraction, de Pury and Farquhar (1997)
    # should this be the same os Qsl? 03/02/08 SK
    canopy_sunlit_irradiance(s, rho_cb, rho_cd, I0_dr, I0_df, Kb, Kb1, Kd1, LAI): I_cSun => begin
        I_c_sunlit = begin
            I0_dr * (1 - s) * (1 - exp(-Kb * LAI)) +
            I0_df * (1 - rho_cd) * (1 - exp(-(Kd1 + Kb) * LAI)) * Kd1 / (Kd1 + Kb) +
            I0_dr * ((1 - rho_cb) * (1 - exp(-(Kb1 + Kb) * LAI)) * Kb1 / (Kb1 + Kb) - (1 - s) * (1 - exp(-2Kb * LAI)) / 2)
        end
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # I_cSh: The irradiance absorbed by the shaded fraction, de Pury and Farquhar (1997)
    canopy_shaded_irradiance(I_c, I_cSun): I_cSh => (I_c - I_cSun) ~ track(u"μmol/m^2/s" #= Quanta =#)

    ######
    # Q? #
    ######

    # sunlit_photon_flux_density(_sunlit_Q) ~ track
    # shaded_photon_flux_density(_shaded_Q) ~ track

    # Qtot: total irradiance (dir + dif) at depth L, simple empirical approach
    irradiance_Q_tot(I0_tot, s, Kb, Kd; L): Q_tot => begin
        I0_tot * exp(-sqrt(1 - s) * ((Kb + Kd) / 2) * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # Qbt: total beam radiation at depth L
    irradiance_Q_bt(I0_dr, s, Kb; L): Q_bt => begin
        I0_dr * exp(-sqrt(1 - s) * Kb * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # net diffuse flux at depth of L within canopy
    irradiance_Q_d(I0_dr, s, Kd; L): Q_d => begin
        I0_df * exp(-sqrt(1 - s) * Kd * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # weighted average absorved diffuse flux over depth of L within canopy
    # accounting for exponential decay, Campbell p261
    irradiance_Q_dm(LAI, I0_df, s, Kd): Q_dm => begin
        if LAI > 0
            # Integral Qd / Integral L
            I0_df * (1 - exp(-sqrt(1 - s) * Kd * LAI)) / (sqrt(1 - s) * Kd * LAI)
        else
            0
        end
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # unintercepted beam (direct beam) flux at depth of L within canopy
    irradinace_Q_b(I0_dr, Kb; L): Q_b => begin
        I0_dr * exp(-Kb * L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # mean flux density on sunlit leaves
    irradiance_Q_sunlit(I0_dr, Kb, Q_sh) => begin
        I0_dr * Kb + Q_sh
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # flux density on sunlit leaves at delpth L
    irradiance_Q_sunlit_at(I0_dr, Kb; L) => begin
        I0_dr * Kb + Q_sh_at(L=L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # mean flux density on shaded leaves over LAI
    irradiance_Q_shaded(Q_dm, Q_scm): Q_sh => begin
        # It does not include soil reflection
        Q_dm + Q_scm
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # diffuse flux density on shaded leaves at depth L
    irradiance_Q_shaded_at(Q_d, Q_sc; L): Q_sh_at => begin
        # It does not include soil reflection
        Q_d(L=L) + Q_sc(L=L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # weighted average of Soil reflectance over canopy accounting for exponential decay
    irradiance_Q_soilm(LAI, rho_soil, s, Kd, Q_soil): Q_soilm => begin
        if LAI > 0
            # Integral Qd / Integral L
            Q_soil * rho_soil * (1 - exp(-sqrt(1 - s) * Kd * LAI)) / (sqrt(1 - s) * Kd * LAI)
        else
            0
        end
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # weighted average scattered radiation within canopy
    irradiance_Q_scm(LAI, rho_soil, s, Kd, Q_soil, Q_soilm, I0_dr, Kb): Q_scm => begin
        if LAI > 0
            # Integral Qd / Integral L
            Q_soilm = Q_soil * rho_soil * (1 - exp(-sqrt(1 - s) * Kd * LAI)) / (sqrt(1 - s) * Kd * LAI)

            # total beam including scattered absorbed by canopy
            #FIXME should the last part be multiplied by LAI like others?
            #TODO simplify by using existing variables (i.e. Q_bt, Q_b)
            total_beam = I0_dr * (1 - exp(-sqrt(1 - s) * Kb * LAI)) / (sqrt(1 - s) * Kb)
            # non scattered beam absorbed by canopy
            nonscattered_beam = I0_dr * (1 - exp(-Kb * LAI)) / Kb
            (total_beam - nonscattered_beam) / LAI
            # Campbell and Norman (1998) p 261, Average between top (where scattering is 0) and bottom.
            #(self.Q_bt(L=LAI) - Q_b(L=LAI)) / 2
        else
            0
        end
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    # scattered radiation at depth L in the canopy
    irradiance_Q_sc(Q_bt, Q_b; L): Q_sc => begin
        # total beam - nonscattered beam at depth L
        Q_bt(L=L) - Q_b(L=L)
    end ~ call(u"μmol/m^2/s" #= Quanta =#)

    # total PFD at the soil sufrace under the canopy
    irradiance_Q_soil(LAI, Q_tot): Q_soil => Q_tot(L=LAI) ~ track(u"μmol/m^2/s" #= Quanta =#)

    ###################
    # Leaf Area Index #
    ###################

    sunrisen(elevation_angle, minimum_elevation_angle=5u"°") => begin
        elevation_angle > minimum_elevation_angle
    end ~ flag

    # sunlit LAI assuming closed canopy; thus not accurate for row or isolated canopy
    sunlit_leaf_area_index(sunrisen, Kb, LAI): LAI_sunlit => begin
        sunrisen ? (1 - exp(-Kb * LAI)) / Kb : 0
    end ~ track(u"cm^2/m^2")

    # shaded LAI assuming closed canopy
    shaded_leaf_area_index(LAI, LAI_sunlit): LAI_shaded => begin
        LAI - LAI_sunlit
    end~ track(u"cm^2/m^2")

    # sunlit fraction of current layer
    sunlit_fraction(sunrisen, Kb; L) => begin
        sunrisen ? exp(-Kb * L) : 0
    end ~ call

    shaded_fraction(sunlit_fraction; L) => begin
        1 - sunlit_fraction(L=L)
    end ~ call
end
