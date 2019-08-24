@system Count(Trait) begin
    total_growing_leaves(x="p.nodal_units[*].leaf.growing") => (isempty(x) ? 0 : sum(x)) ~ track::Int

    total_initiated_leaves(l="p.pheno.leaves_initiated") => l ~ track::Int

    total_appeared_leaves(l="p.pheno.leaves_appeared") => l ~ track::Int

    total_mature_leaves(x="p.nodal_units[*].leaf.mature") => (isempty(x) ? 0 : sum(x)) ~ track::Int

    total_dropped_leaves(x="p.nodal_units[*].leaf.dropped") => (isempty(x) ? 0 : sum(x)) ~ track::Int
end
