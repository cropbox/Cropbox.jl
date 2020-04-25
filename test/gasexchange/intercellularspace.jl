@system IntercellularSpace(Weather) begin
    A_net ~ hold
    #TODO: interface between boundary/stomata/intercellular space (i.e. soil layers?)
    gvc ~ hold

    #FIXME: duplicate in Stomata
    Ca(CO2, P_air): co2_air => (CO2 * P_air) ~ track(u"μbar")

    #HACK: high temperature simulation requires higher upper bound
    Cimax(Ca): intercellular_co2_upper_limit => 2Ca ~ track(u"μbar")
    Cimin: intercellular_co2_lower_limit => 0 ~ preserve(u"μbar")
    Ci(Ca, Ci, A_net, gvc): intercellular_co2 => begin
        Ca - Ci ⩵ A_net / gvc
    end ~ bisect(min=Cimin, upper=Cimax, u"μbar")
end
