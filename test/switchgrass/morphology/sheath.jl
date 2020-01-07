@system Sheath(Organ) begin
    rank ~ ::Int(override) # preserve

    #FIXME sheath biomass
    mass => 0 ~ track(u"g")
end
