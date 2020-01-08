@system Germination(Stage) begin
    planting_date ~ hold

    maximum_germination_rate: GR_max => 0.45 ~ preserve(u"d^-1", parameter)

    germination(r=GR_max, β=BF.ΔT, germinating) => begin
        germinating ? r * β : zero(r)
    end ~ accumulate

    germinateable(planting_date, t=calendar.time) => (t >= planting_date) ~ flag
    germinated(germination, begin_from_emergence) => germination >= 0.5 ~ flag
    germinating(a=germinateable, b=germinated) => (a && !b) ~ flag
end
