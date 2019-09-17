@system NodalUnit(Organ) begin
    rank ~ ::Int(override) # preserve
    leaf(context, phenology, rank) => Leaf(; context=context, phenology=phenology, rank=rank) ~ ::Leaf
    sheath(context, phenology, rank) => Sheath(; context=context, phenology=phenology, rank=rank) ~ ::Sheath

    mass(l=leaf.mass, s=sheath.mass) => (l + s) ~ track(u"g")
end
