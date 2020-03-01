@system IntercellularSpace(WeatherStub) begin
    A_net ~ hold
    #TODO: interface between boundary/stomata/intercellular space (i.e. soil layers?)
    rvc ~ hold

    #FIXME: duplicate in Stomata
    Ca(CO2, P_air): co2_air => (CO2 * P_air) ~ track(u"μbar")

    #HACK: high temperature simulation requires higher upper bound
    Cimax(Ca): intercellular_co2_upper_limit => 4Ca ~ track(u"μbar")
    Cimin: intercellular_co2_lower_limit => 0 ~ preserve(u"μbar")
    Ci(Ca, A_net, rvc): intercellular_co2 => begin
        Ca - A_net * rvc
    end ~ bisect(lower=Cimin, upper=Cimax, u"μbar")
end
