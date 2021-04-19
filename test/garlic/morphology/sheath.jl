@system Sheath(Organ) begin
    rank ~ ::int(override) # preserve

    #FIXME sheath biomass
    mass => 0 ~ track(u"g")
end
