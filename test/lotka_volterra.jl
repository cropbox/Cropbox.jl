@testset "lotka volterra" begin
    @system LotkaVolterra(Controller) begin
        prey_birth_rate: a => 1.0 ~ preserve(u"hr^-1", parameter)
        prey_death_rate: b => 0.1 ~ preserve(u"hr^-1", parameter)
        predator_death_rate: c => 1.5 ~ preserve(u"hr^-1", parameter)
        predator_reproduction_rate: d => 0.75 ~ preserve(parameter)
        prey_initial_population: H0 => 10.0 ~ preserve(parameter)
        predator_initial_population: P0 => 5.0 ~ preserve(parameter)
        prey_population(a, b, H, P): H => a*H - b*H*P ~ accumulate(init=H0)
        predator_population(b, c, d, H, P): P => d*b*H*P - c*P ~ accumulate(init=P0)
    end
    r = simulate(LotkaVolterra, stop=1200, config=(
        :Clock => (:step => 1u"minute"),
    ))
    @test r[!, :tick][end] > 20u"hr"
    Cropbox.plot(r, :tick, [:prey_population, :predator_population])
end
