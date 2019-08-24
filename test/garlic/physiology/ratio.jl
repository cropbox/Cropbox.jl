@system Ratio(Trait) begin
    carbon_to_mass(r="p.weight.C_to_CH2O_ratio") => begin
        # 40% C, See Kim et al. (2007) EEB
        r
    end ~ preserve

    shoot_to_root => 0.7 ~ preserve

    root_to_shoot(shoot_to_root) => (1 - shoot_to_root) ~ preserve

    leaf_to_stem => 0.9 ~ preserve

    stem_to_leaf(leaf_to_stem) => (1 - leaf_to_stem) ~ preserve

    initial_leaf(shoot_to_root, leaf_to_stem, primordia="p.primordia") => begin
        #TODO how to handle primordia?
        shoot_to_root * leaf_to_stem / primordia
    end ~ preserve
end
