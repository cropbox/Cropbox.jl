@system NodalUnit(Organ) begin
    rank ~ ::Int(override) # preserve
    leaf(context, phenology, rank) ~ ::Leaf
    sheath(context, phenology, rank) ~ ::Sheath

    mass(l=leaf.mass, s=sheath.mass) => (l + s) ~ track(u"g")
end
