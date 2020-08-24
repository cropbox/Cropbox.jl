@system ThermalTime begin
    T: temperature ~ track(u"°C", override)
    Δt(context.clock.step): timestep ~ preserve(u"hr")
    ΔT: magnitude ~ track
    r(ΔT, Δt): rate => ΔT / Δt ~ track(u"hr^-1")
end

@system GrowingDegree(ThermalTime) begin
    Tb: base_temperature ~ preserve(u"°C", extern, parameter)
    To: optimal_temperature ~ preserve(u"°C", optional, extern, parameter)
    Tx: maximum_temperature ~ preserve(u"°C", optional, extern, parameter)

    ΔT(T, Tb, To, Tx): magnitude => begin
        T = !isnothing(To) ? min(T, To) : T
        T = !isnothing(Tx) && T >= Tx ? Tb : T
        T - Tb
    end ~ track(u"K", min=0)
    r(ΔT, Δt): rate => ΔT / Δt ~ track(u"K/hr")
end

@system BetaFunction(ThermalTime) begin
    Tn: minimum_temperature => 0 ~ preserve(u"°C", extern, parameter)
    To: optimal_temperature ~ preserve(u"°C", extern, parameter)
    Tx: maximum_temperature ~ preserve(u"°C", extern, parameter)
    β: beta => 1 ~ preserve(parameter)

    ΔT(T, Tn, To, Tx, β): magnitude => begin
        # beta function, See Yin et al. (1995), Ag For Meteorol., Yan and Hunt (1999) AnnBot, SK
        if (Tn < T < Tx) && (Tn < To < Tx)
            Ton = To - Tn
            Txo = Tx - To
            f = (T - Tn) / Ton
            g = (Tx - T) / Txo
            α = β * (Ton / Txo)
            f^α * g^β
        else
            0.
        end
    end ~ track
end

@system Q10Function(ThermalTime) begin
    To: optimal_temperature ~ preserve(u"°C", extern, parameter)
    Q10 => 2 ~ preserve(extern, parameter)

    #FIXME: Q10 isn't actually a thermal function like others (not a rate, check unit)
    ΔT(T, To, Q10): magnitude => begin
        Q10^((T - To) / 10u"K")
    end ~ track
end

export GrowingDegree, BetaFunction, Q10Function
