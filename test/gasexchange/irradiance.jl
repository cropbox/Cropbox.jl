@system Irradiance begin
    PFD ~ hold

    #HACK: should be PPFD from Radiation
    PPFD(PFD): photosynthetic_photon_flux_density ~ track(u"μmol/m^2/s")

    #FIXME: duplicate? already considered in Radiation?
    #FIXME: how is (1 - δ) related to α in EnergyBalance?
    # leaf reflectance + transmittance
    δ: leaf_scattering => 0.15 ~ preserve(parameter)
    f: leaf_spectral_correction => 0.15 ~ preserve(parameter)

    Ia(PPFD, δ): absorbed_irradiance => begin
        PPFD * (1 - δ)
    end ~ track(u"μmol/m^2/s" #= Quanta =#)

    I2(Ia, f): effective_irradiance => begin
        Ia * (1 - f) / 2 # useful light absorbed by PSII
    end ~ track(u"μmol/m^2/s" #= Quanta =#)
end