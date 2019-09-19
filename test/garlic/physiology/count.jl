@system Count begin
    nodal_units ~ hold

    leaves_growing(x=nodal_units["*"].leaf.growing) => sum(x) ~ track::Int
    leaves_mature(x=nodal_units["*"].leaf.mature) => sum(x) ~ track::Int
    leaves_dropped(x=nodal_units["*"].leaf.dropped) => sum(x) ~ track::Int
end
