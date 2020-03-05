@system Transpiration(WeatherStub) begin
    T: leaf_temperature ~ hold
    gv: total_conductance_h2o ~ hold

    D(T, T_air, RH, #= P_air, =# ea=vp.ambient, es=vp.saturation): leaf_vapor_pressure_deficit => begin
        Es = es(T)
        Ea = ea(T_air, RH)
        Es - Ea # MAIZSIM: / (1 - (Es + Ea) / P_air)
    end ~ track(u"kPa")

    E(gv, D): transpiration => gv * D ~ track(u"mmol/m^2/s" #= H2O =#)
end
