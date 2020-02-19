@system Count begin
    NU: nodal_units ~ hold

    leaves_growing(x=NU["*"].leaf.growing) => sum(x) ~ track::Int
    leaves_mature(x=NU["*"].leaf.mature) => sum(x) ~ track::Int
    leaves_dropped(x=NU["*"].leaf.dropped) => sum(x) ~ track::Int
end
