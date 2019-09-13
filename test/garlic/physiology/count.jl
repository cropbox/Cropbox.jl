@system Count begin
    nodal_units ~ hold

    leaves_growing(x=nodal_units["*"].leaf.growing) => (isempty(x) ? 0 : sum(x)) ~ track::Int
    leaves_mature(x=nodal_units["*"].leaf.mature) => (isempty(x) ? 0 : sum(x)) ~ track::Int
    leaves_dropped(x=nodal_units["*"].leaf.dropped) => (isempty(x) ? 0 : sum(x)) ~ track::Int
end
