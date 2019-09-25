@system Sheath(Organ) begin
    rank ~ ::Int(extern) # preserve

    #FIXME sheath biomass
    mass => 0 ~ track(u"g")
end
