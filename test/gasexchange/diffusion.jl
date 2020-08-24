@system Diffusion begin
    Dw: diffusion_coeff_for_water_vapor_in_air_at_20 => 24.2 ~ preserve(u"mm^2/s", parameter)
    Dc: diffusion_coeff_for_co2_in_air_at_20 => 14.7 ~ preserve(u"mm^2/s", parameter)
    Dh: diffusion_coeff_for_heat_in_air_at_20 => 21.5 ~ preserve(u"mm^2/s", parameter)
    Dm: diffusion_coeff_for_momentum_in_air_at_20 => 15.1 ~ preserve(u"mm^2/s", parameter)
end
