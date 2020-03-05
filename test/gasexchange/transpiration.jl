@system Transpiration(WeatherStub) begin
    T: leaf_temperature ~ hold
    gv: total_conductance_h2o ~ hold

    D0(T, T_air, RH, P_air, ea=vp.ambient, es=vp.saturation): leaf_vapor_pressure_deficit_maizsim => begin
        Es = es(T)
        Ea = ea(T_air, RH)
        ((Es - Ea) / P_air) / (1 - (Es + Ea) / P_air) * P_air
    end ~ track(u"kPa")

    ET(gv, D0): evapotranspiration => begin
        ET = gv * D0
        max(ET, zero(ET)) # 04/27/2011 dt took out the 1000 everything is moles now
    end ~ track(u"mmol/m^2/s" #= H2O =#)

    D(T, T_air, RH, #= P_air, =# ea=vp.ambient, es=vp.saturation): leaf_vapor_pressure_deficit => begin
        Es = es(T)
        Ea = ea(T_air, RH)
        Es - Ea
    end ~ track(u"kPa")

    E(gv, D): transpiration => gv * D ~ track(u"mmol/m^2/s" #= H2O =#)
end
