@system Nitrogen begin
    SPAD: SPAD_greenness ~ preserve(parameter)
    SNa: SPAD_N_coeff_a ~ preserve(u"g/m^2", parameter)
    SNb: SPAD_N_coeff_b ~ preserve(u"g/m^2", parameter)
    N(SPAD, a=SNa, b=SNb): leaf_nitrogen_content => begin
        a*SPAD + b
    end ~ preserve(u"g/m^2", parameter)
end
