@testset "lotka volterra" begin
    @system LotkaVolterra(Controller) begin
        a: prey_birth_rate => 1.0 ~ preserve(u"hr^-1", parameter)
        b: prey_death_rate => 0.1 ~ preserve(u"hr^-1", parameter)
        c: predator_death_rate => 1.5 ~ preserve(u"hr^-1", parameter)
        d: predator_reproduction_rate => 0.75 ~ preserve(parameter)
        H0: prey_initial_population => 10.0 ~ preserve(parameter)
        P0: predator_initial_population => 5.0 ~ preserve(parameter)
        H(a, b, H, P): prey_population => a*H - b*H*P ~ accumulate(init=H0)
        P(b, c, d, H, P): predator_population => d*b*H*P - c*P ~ accumulate(init=P0)
    end
    r = simulate(LotkaVolterra, stop=1200, config=(
        :Clock => (:step => 1u"minute"),
    ))
    @test r[!, :tick][end] > 20u"hr"
    Cropbox.plot(r, :tick, [:H, :P], ylabel=["prey", "predator"]) |> display
end
