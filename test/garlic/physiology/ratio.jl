@system Ratio begin
    primordia ~ hold

    shoot_to_root_ratio => 0.7 ~ preserve

    root_to_shoot_ratio(shoot_to_root_ratio) => (1 - shoot_to_root_ratio) ~ preserve

    leaf_to_stem_ratio => 0.9 ~ preserve

    stem_to_leaf_ratio(leaf_to_stem_ratio) => (1 - leaf_to_stem_ratio) ~ preserve

    initial_leaf_ratio(shoot_to_root_ratio, leaf_to_stem_ratio, primordia) => begin
        #TODO how to handle primordia?
        shoot_to_root_ratio * leaf_to_stem_ratio / primordia
    end ~ preserve
end
