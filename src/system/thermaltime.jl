@system GrowingDegreeDays begin
    temperature: T ~ track(u"°C", override)

    base_temperature: Tb ~ preserve(u"°C", parameter)
    optimal_temperature: To ~ preserve(u"°C", optional, parameter)
    maximum_temperature: Tx ~ preserve(u"°C", optional, parameter)

    thermal_time(T=nounit(T), Tb=nounit(Tb), To=nounit(To), Tx=nounit(Tx)): tt => begin
        T = !isnothing(To) ? min(T, To) : T
        T = !isnothing(Tx) && T >= Tx ? Tb : T
        max(T - Tb, 0.)
    end ~ track
end

@system BetaFunction begin
    temperature: T ~ track(u"°C", override)

    minimum_temperature: Tn => 0 ~ preserve(u"°C", parameter)
    optimal_temperature: To ~ preserve(u"°C", parameter)
    maximum_temperature: Tx ~ preserve(u"°C", parameter)
    beta: β => 1 ~ preserve(parameter)

    thermal_time(T=nounit(T), Tn=nounit(Tn), To=nounit(To), Tx=nounit(Tx), β): tt => begin
        !(Tn < T < Tx) && return 0.
        !(Tn < To < Tx) && return 0.
        # beta function, See Yin et al. (1995), Ag For Meteorol., Yan and Hunt (1999) AnnBot, SK
        Ton = To - Tn
        Txo = Tx - To
        f = (T - Tn) / Ton
        g = (Tx - T) / Txo
        α = β * Ton / Txo
        f^α * g^β
    end ~ track
end

@system Q10Function begin
    temperature: T ~ track(u"°C", override)

    optimal_temperature: To ~ preserve(u"°C", parameter)
    Q10 => 2 ~ preserve(parameter)

    thermal_time(T=nounit(T), To=nounit(To), Q10): tt => begin
        Q10^((T - To) / 10)
    end ~ track
end

export GrowingDegreeDays, BetaFunction, Q10Function
