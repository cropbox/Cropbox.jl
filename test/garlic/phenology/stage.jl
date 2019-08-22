@system Stage begin
    phenology: [pheno, p] ~ ::System(override)

    temperature(p): T => p ~ drive(u"°C")
    optimal_temperature(p): T_opt ~ drive(u"°C")
    ceiling_temperature(p): T_ceil ~ drive(u"°C")

    ready => false ~ flag
    over => false ~ flag
    ing(ready, over) => (ready && !over) ~ flag
end
