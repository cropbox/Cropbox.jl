#TODO implement proper soil module
@system Soil begin
    T_soil => 10 ~ track(u"°C")
    leaf_water_potential: WP_leaf => 0 ~ track(u"MPa") # pressure - leaf water potential MPa...
    total_root_weight => 0 ~ track(u"g")
end

# import Base: show
# show(io::IO, s::Soil) = print(io, "$(s.T_soil)\n$(s.WP_leaf)\n$(s.total_root_weight)")
