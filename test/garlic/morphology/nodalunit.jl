@system NodalUnit(Organ) begin
    rank => 0 ~ preserve::Int(override)
    leaf(context, plant) => Leaf(; context=context, plant=plant, nodal_unit=self) ~ ::System
    sheath(context, plant) => Sheath(; context=context, plant=plant, nodal_unit=self) ~ ::System

    mass(l=leaf.mass, s=sheath.mass) => (l + s) ~ track(u"g")
end
