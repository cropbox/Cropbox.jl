@system Stage begin
    phenology: [pheno, p] ~ ::System(override)

    temperature(p): T => p ~ drive(u"°C")
    optimal_temperature(p): T_opt => p ~ drive(u"°C")
    ceiling_temperature(p): T_ceil => p ~ drive(u"°C")

    #TODO: need override implementation for include()
    #ready => false ~ flag
    #over => false ~ flag
    ing(ready, over) => (ready && !over) ~ flag
end
