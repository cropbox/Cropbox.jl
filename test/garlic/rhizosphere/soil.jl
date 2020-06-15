#TODO implement proper soil module
@system Soil begin
    T_soil => 10 ~ track(u"°C")
    WP_leaf: leaf_water_potential => 0 ~ track(u"MPa") # pressure - leaf water potential MPa...
    total_root_weight => 0 ~ track(u"g")
end

@system SoilStub begin
    soil ~ hold

    WP_leaf(soil.WP_leaf) ~ track(u"MPa")
end

# Base.show(io::IO, s::Soil) = print(io, "$(s.T_soil)\n$(s.WP_leaf)\n$(s.total_root_weight)")
