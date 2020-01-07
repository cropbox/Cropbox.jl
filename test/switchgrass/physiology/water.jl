@system Water begin
    #FIXME check unit (w.r.t photosynthesis.ET_supply)
    #FIXME check name (probably not the same as photosynthesis.ET_supply)
    # ET_supply?
    water_supply => 0 ~ track(u"g/hr")
end
