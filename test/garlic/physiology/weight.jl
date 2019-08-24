@system Weight begin
    CO2 => 44.0098 ~ preserve(u"g/μmol")
    C => 12.0107 ~ preserve(u"g/μmol")
    CH2O => 30.031 ~ preserve(u"g/μmol")
    H2O => 18.01528 ~ preserve(u"g/μmol")

    C_to_CH2O_ratio(C, CH2O) => begin
        C / CH2O # 0.40
    end ~ preserve
end
