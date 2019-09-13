@system Weight begin
    CO2_weight => 44.0098 ~ preserve(u"g/μmol")
    C_weight => 12.0107 ~ preserve(u"g/μmol")
    CH2O_weight => 30.031 ~ preserve(u"g/μmol")
    H2O_weight => 18.01528 ~ preserve(u"g/μmol")

    C_to_CH2O_ratio(C_weight, CH2O_weight) => begin
        C_weight / CH2O_weight # 0.40
    end ~ preserve
end
