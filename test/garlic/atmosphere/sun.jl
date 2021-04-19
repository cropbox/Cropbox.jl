# Unit to calculate solar geometry including solar elevation, declination,
#  azimuth etc using TSolar class. Data are hidden. 03/15/00 SK
# - 1st Revision 10/10/00: Changed to dealing only upto the top of the canopy. Radiation transter within the canopy is now a separate module.
# - added functins to calculate global radiation, atmospheric emissivity, etc as in Spitters et al. (1986), 3/18/01, SK
# 24Dec03, SK
# - added a function to calculate day length based on Campbell and Norman (1998) p 170,
# - added overloads to SetVal
# 2Aug04, SK
# - Translated to C++ from Delphi
# - revised some functions according to "An introduction to solar radiaiton" by Iqbal (1983)
# - (To Do) Add algorithms for instantaneous diffuse and direct radiation predictions from daily global solar radiation for given time
# - (To Do) This can be done by first applying sinusoidal model to the daily data to simulate hourly global solar radiation
# - (To Do) Then the division model of diffuse and direct radiations was applied
# - added direct and diffuse separation functions according to Weiss and Norman (1985), 3/16/05

@system Location begin
    lat: latitude => 36u"°" ~ preserve(u"°", parameter)
    long: longitude => 128u"°" ~ preserve(u"°", parameter)
    alt: altitude => 20u"m" ~ preserve(u"m", parameter)
end

import Dates

@system Sun begin
    #TODO override Location
    loc(context): location ~ ::Location #(override)
    calendar ~ ::Calendar(override)
    weather ~ ::Weather(override)

    # @derive time? -- takes account different Julian day conventions (03-01 vs. 01-01)
    t(calendar.time): datetime ~ track::datetime
    d(t): day => Dates.dayofyear(t) ~ track::int(u"d")
    h(t): hour => Dates.hour(t) ~ track::int(u"hr")

    ϕ(loc.lat): latitude ~ track(u"°") # DO NOT convert to radians for consistency
    λ(loc.long): longitude ~ track(u"°") # leave it as in degrees, used only once for solar noon calculation
    alt(loc.alt): altitude ~ track(u"m")

    #TODO: fix inconsistent naming of PAR vs. PFD
    PAR(weather.PFD): photosynthetic_active_radiation ~ track(u"μmol/m^2/s") # Quanta
    τ: transmissivity => 0.5 ~ preserve(parameter) # atmospheric transmissivity, Goudriaan and van Laar (1994) p 30

    #####################
    # Solar Coordinates #
    #####################

    #HACK always use degrees for consistency and easy tracing
    #FIXME pascal version of LightEnv uses iqbal()
    δ(declination_angle_spencer): declination_angle ~ track(u"°")

    # Goudriaan 1977
    declination_angle_goudriaan(d) => begin
        g = 2pi * (d + 10u"d") / 365u"d"
        -23.45u"°" * cos(g)
    end ~ track(u"°")

    # Resenberg, blad, verma 1982
    declination_angle_resenberg(d) => begin
        g = 2pi * (d - 172u"d") / 365u"d"
        23.5u"°" * cos(g)
    end ~ track(u"°")

    # Iqbal (1983) Pg 10 Eqn 1.3.3, and sundesign.com
    declination_angle_iqbal(d) => begin
        g = 2pi * (d + 284u"d") / 365u"d"
        23.45u"°" * sin(g)
    end ~ track(u"°")

    # Campbell and Norman, p168
    declination_angle_campbell(d) => begin
        a = deg2rad(356.6 + 0.9856u"d^-1" * d)
        b = deg2rad(278.97 + 0.9856u"d^-1" * d + 1.9165sin(a))
        asind(0.39785sin(b))
    end ~ track(u"°")

    # Spencer equation, Iqbal (1983) Pg 7 Eqn 1.3.1. Most accurate among all
    declination_angle_spencer(d) => begin
        # gamma: day angle
        g = 2pi * (d - 1u"d") / 365u"d"
        0.006918 - 0.399912cos(g) + 0.070257sin(g) - 0.006758cos(2g) + 0.000907sin(2g) -0.002697cos(3g) + 0.00148sin(3g)
    end ~ track(u"rad")

    dph: degree_per_hour => 360u"°" / 24u"hr" ~ preserve(u"°/hr")

    # LC is longitude correction for Light noon, Wohlfart et al, 2000; Campbell & Norman 1998
    LC(λ, dph): longitude_correction => begin
        # standard meridian for pacific time zone is 120 W, Eastern Time zone : 75W
        # LC is positive if local meridian is east of standard meridian, i.e., 76E is east of 75E
        #standard_meridian = -120
        meridian = round(u"hr", λ / dph) * dph
        #FIXME use standard longitude sign convention
        #(long - meridian) / dph
        #HACK this assumes inverted longitude sign that MAIZSIM uses
        (meridian - λ) / dph
    end ~ track(u"hr")

    ET(d): equation_of_time => begin
        f = (279.575 + 0.9856u"d^-1" * d)*u"°"
        (-104.7sin(f) + 596.2sin(2f) + 4.3sin(3f) - 12.7sin(4f) -429.3cos(f) - 2.0cos(2f) + 19.3cos(3f)) / (60 * 60)
    end ~ track(u"hr")

    solar_noon(LC, ET) => 12u"hr" - LC - ET ~ track(u"hr")

    # θs: zenith angle
    hour_angle_at(ϕ, δ; θs(u"°")) => begin
        # this value should never become negative because -90 <= latitude <= 90 and -23.45 < decl < 23.45
        #HACK is this really needed for crop models?
        # preventing division by zero for N and S poles
        #denom = fmax(denom, 0.0001)
        # sunrise/sunset hour angle
        #TODO need to deal with lat_bound to prevent tan(90)?
        #lat_bound = radians(68)? radians(85)?
        # cos(h0) at cos(theta_s) = 0 (solar zenith angle = 90 deg == elevation angle = 0 deg)
        #-tan(ϕ) * tan(δ)
        c = (cos(θs) - sin(ϕ) * sin(δ)) / (cos(ϕ) * cos(δ))
        # c > 1: in the polar region during the winter, sun does not rise
        # c < -1: white nights during the summer in the polar region
        c = clamp(c, -1, 1)
        acosd(c)
    end ~ call(u"°")

    hour_angle_at_horizon(hour_angle_at) => hour_angle_at(90u"°") ~ track(u"°")

    # from Iqbal (1983) p 16
    half_day_length(hour_angle_at_horizon, dph) => (hour_angle_at_horizon / dph) ~ track(u"hr")
    day_length(half_day_length) => 2half_day_length ~ track(u"hr")

    sunrise(solar_noon, half_day_length) => (solar_noon - half_day_length) ~ track(u"hr")
    sunset(solar_noon, half_day_length) => (solar_noon + half_day_length) ~ track(u"hr")

    hour_angle(h, solar_noon, dph) => ((h - solar_noon) * dph) ~ track(u"°")

    αs(h=hour_angle, δ, ϕ): elevation_angle => begin
        #FIXME When time gets the same as solarnoon, this function fails. 3/11/01 ??
        asind(cos(h) * cos(δ) * cos(ϕ) + sin(δ) * sin(ϕ))
    end ~ track(u"°")

    ts(αs): positive_elevation_angle ~ track(u"°", min=0)

    θs(αs): zenith_angle => (90u"°" - αs) ~ track(u"°")

    # The solar azimuth angle is the angular distance between due South and the
    # projection of the line of sight to the sun on the ground.
    # View point from south, morning: +, afternoon: -
    # See An introduction to solar radiation by Iqbal (1983) p 15-16
    # Also see https://www.susdesign.com/sunangle/
    ϕs(αs, δ, ϕ): azimuth_angle => begin
        acosd((sin(δ) - sin(αs) * sin(ϕ)) / (cos(αs) * cos(ϕ)))
    end ~ track(u"°")

    ###################
    # Solar Radiation #
    ###################

    # atmospheric pressure in kPa (default = 100 kPa?)
    p(altitude): atmospheric_pressure => begin
        # campbell and Norman (1998), p 41
        101.3exp(-altitude / 8200u"m")
    end ~ track(u"kPa")

    m(p, ts): optical_air_mass_number => begin
        #FIXME check 101.3 is indeed in kPa
        #iszero(t_s) ? 0. : p / (101.3u"kPa" * sin(t_s))
        p / (101.3u"kPa" * sin(ts))
    end ~ track

    SC: solar_constant => 1370 ~ preserve(u"W/m^2", parameter)

    # Campbell and Norman's global solar radiation, this approach is used here
    #TODO rename to insolation? (W/m2)
    solar_radiation(ts, d, SC) => begin
        # solar constant, Iqbal (1983)
        #FIXME better to be 1361 or 1362 W/m-2?
        g = 2pi * (d - 10u"d") / 365u"d"
        SC * sin(ts) * (1 + 0.033cos(g))
    end ~ track(u"W/m^2")

    directional_solar_radiation(Fdir, solar_radiation) => begin
        Fdir * solar_radiation
    end ~ track(u"W/m^2")

    diffusive_solar_radiation(Fdif, solar_radiation) => begin
        Fdif * solar_radiation
    end ~ track(u"W/m^2")

    Fdir(τ, m): directional_coeff => begin
        # Goudriaan and van Laar's global solar radiation
        #FIXME should be goudriaan() version
        goudriaan(τ) = τ * (1 - diffusive_coeff)
        #FIXME: check if equation is same as campbell()
        # Takakura (1993), p 5.11
        takakura(τ, m) = τ^m
        # Campbell and Norman (1998), p 173
        campbell(τ, m) = τ^m
        campbell(τ, m)
    end ~ track

    # Fdif: Fraction of diffused light
    Fdif(τ, m): diffusive_coeff => begin
        # Goudriaan and van Laar's global solar radiation
        goudriaan(τ) = begin
            # clear sky : 20% diffuse
            if τ >= 0.7
                0.2
            # cloudy sky: 100% diffuse
            elseif τ <= 0.3
                1
            # inbetween
            else
                1.6 - 2τ
            end
        end
        # Takakura (1993), p 5.11
        takakura(τ, m) = (1 - τ^m) / (1 - 1.4log(τ)) / 2
        # Campbell and Norman (1998), p 173
        campbell(τ, m) = 0.3(1 - τ^m)
        campbell(τ, m)
    end ~ track

    directional_fraction(Fdif, Fdir) => (1 / (1 + Fdif/Fdir)) ~ track
    diffusive_fraction(Fdir, Fdif) => (1 / (1 + Fdir/Fdif)) ~ track

    # PARfr
    #TODO better naming: extinction? transmitted_fraction?
    PARfr(τ): photosynthetic_coeff => begin
        #if self.elevation_angle <= 0:
        #    0
        #TODO: implement Weiss and Norman (1985), 3/16/05
        weiss() = nothing
        # Goudriaan and van Laar (1994)
        goudriaan(τ) = begin
            # clear sky (τ >= 0.7): 45% is PAR
            if τ >= 0.7
                0.45
            # cloudy sky (τ <= 0.3): 55% is PAR
            elseif τ <= 0.3
                0.55
            else
                0.625 - 0.25τ
            end
        end
        goudriaan(τ)
    end ~ track

    # PARtot: total PAR (umol m-2 s-1) on horizontal surface (PFD)
    PARtot(PAR): photosynthetic_active_radiation_total ~ track(u"μmol/m^2/s") # Quanta

    Q: photosynthetic_active_radiation_conversion_factor => begin
        # 4.55 is a conversion factor from W to photons for solar radiation, Goudriaan and van Laar (1994)
        # some use 4.6 i.e., Amthor 1994, McCree 1981, Challa 1995.
        4.6
    end ~ preserve(u"μmol/J", parameter)

    PARtot2(solar_radiation, PARfr, Q): photosynthetic_active_radiation_total2 => begin
        # conversion factor from W/m2 to PFD (umol m-2 s-1) for PAR waveband (median 550 nm of 400-700 nm) of solar radiation,
        # see Campbell and Norman (1994) p 149
        solar_radiation * PARfr * Q
    end ~ track(u"μmol/m^2/s") # Quanta

    # PARdir
    PARdir(PARtot, directional_fraction): directional_photosynthetic_radiation => (directional_fraction * PARtot) ~ track(u"μmol/m^2/s") # Quanta

    # PARdif
    PARdif(PARtot, diffusive_fraction): diffusive_photosynthetic_radiation => (diffusive_fraction * PARtot) ~ track(u"μmol/m^2/s") # Quanta
end

@system SunController(Controller) begin
    calendar(context) ~ ::Calendar
    weather(context, calendar) ~ ::Weather
    s(context, calendar, weather): sun ~ ::Sun
end

plot_sun(v, d=3u"d"; kw...) = begin
    o = (
        :Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"Asia/Seoul")),
        :Weather => (:store => loadwea("$(@__DIR__)/../data/2007.wea", tz"Asia/Seoul")),
    )
    r = simulate(SunController, stop=d, config=o, base=:sun)
    visualize(r, :time, v; kw...)
end

test_sun(d=3u"d") = foreach(v -> display(plot_sun(v, d)), [
    :δ, # declination_angle
    :αs, # elevation_angle
    :Fdir, # directional_coeff
    :Fdif, # diffusive_coeff
])
