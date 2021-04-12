@system Nitrogen begin
    SPAD: SPAD_greenness ~ preserve(parameter)
    _a: SPAD_N_coeff_a ~ preserve(u"g/m^2", parameter)
    _b: SPAD_N_coeff_b ~ preserve(u"g/m^2", parameter)
    _c: SPAD_N_coeff_c ~ preserve(u"g/m^2", parameter)
    N(SPAD, _a, _b, _c): leaf_nitrogen_content => begin
        a*SPAD^2 + b*SPAD + c
    end ~ preserve(u"g/m^2", parameter)

    Np(N, SLA) => N * SLA ~ track(u"percent")
    SLA: specific_leaf_area => 200 ~ preserve(u"cm^2/g")
end
