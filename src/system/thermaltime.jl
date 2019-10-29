@system ThermalTime begin
    temperature: T ~ track(u"°C", override)
    timestep(context.clock.step): Δt ~ preserve(u"hr")
    thermal_time: tt ~ track(u"hr^-1")
end

@system GrowingDegree(ThermalTime) begin
    base_temperature: Tb ~ preserve(u"°C", parameter)
    optimal_temperature: To ~ preserve(u"°C", optional, parameter)
    maximum_temperature: Tx ~ preserve(u"°C", optional, parameter)

    thermal_time(T, Tb, To, Tx, Δt): tt => begin
        T = !isnothing(To) ? min(T, To) : T
        T = !isnothing(Tx) && T >= Tx ? Tb : T
        ΔT = max(T - Tb, zero(T))
        ΔT / Δt
    end ~ track(u"K/hr")
end

@system BetaFunction(ThermalTime) begin
    minimum_temperature: Tn => 0 ~ preserve(u"°C", parameter)
    optimal_temperature: To ~ preserve(u"°C", parameter)
    maximum_temperature: Tx ~ preserve(u"°C", parameter)
    beta: β => 1 ~ preserve(parameter)

    thermal_time(T, Tn, To, Tx, β, Δt): tt => begin
        # beta function, See Yin et al. (1995), Ag For Meteorol., Yan and Hunt (1999) AnnBot, SK
        ΔT = if (Tn < T < Tx) && (Tn < To < Tx)
            Ton = To - Tn
            Txo = Tx - To
            f = (T - Tn) / Ton
            g = (Tx - T) / Txo
            α = β * (Ton / Txo)
            f^α * g^β
        else
            0.
        end
        ΔT / Δt
    end ~ track(u"hr^-1")
end

@system Q10Function(ThermalTime) begin
    optimal_temperature: To ~ preserve(u"°C", parameter)
    Q10 => 2 ~ preserve(parameter)

    #FIXME: Q10 isn't actually a thermal function like others (not a rate, check unit)
    thermal_time(T, To, Q10): tt => begin
        Q10^((T - To) / 10u"K")
    end ~ track
end

export GrowingDegree, BetaFunction, Q10Function
