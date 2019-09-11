@system Sheath(Organ) begin
    nodal_unit: nu ~ ::System(override)

    rank(x=nu.rank) ~ track::Int

    #FIXME sheath biomass
    mass => 0 ~ track(u"g")
end
