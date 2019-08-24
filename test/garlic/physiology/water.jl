@system Water(Trait) begin
    #FIXME check unit (w.r.t photosynthesis.ET_supply)
    #FIXME check name (probably not the same as photosynthesis.ET_supply)
    # ET_supply?
    supply => 0 ~ track(u"g/hr")
end
