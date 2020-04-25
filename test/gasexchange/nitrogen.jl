@system Nitrogen begin
    SPAD: SPAD_greenness ~ preserve(parameter)
    SNa: SPAD_N_coeff_a ~ preserve(u"g/m^2", parameter)
    SNb: SPAD_N_coeff_b ~ preserve(u"g/m^2", parameter)
    N(SPAD, a=SNa, b=SNb): nitrogen => begin
        a*SPAD + b
    end ~ track(u"g/m^2")
end
