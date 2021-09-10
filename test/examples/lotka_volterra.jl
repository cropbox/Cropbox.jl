@testset "lotka volterra" begin
    @system LotkaVolterra(Controller) begin
        t(context.clock.time) ~ track(u"yr")
        N(N, P, b, a): prey_population => b*N - a*N*P ~ accumulate(init=N0)
        P(N, P, c, a, m): predator_population => c*a*N*P - m*P ~ accumulate(init=P0)
        N0: prey_initial_population ~ preserve(parameter)
        P0: predator_initial_population ~ preserve(parameter)
        b: prey_birth_rate ~ preserve(u"yr^-1", parameter)
        a: predation_rate ~ preserve(u"yr^-1", parameter)
        c: predator_reproduction_rate ~ preserve(parameter)
        m: predator_mortality_rate ~ preserve(u"yr^-1", parameter)
    end
    config = @config (
        :Clock => (;
            step = 1u"d",
        ),
        :LotkaVolterra => (;
            b = 0.6,
            a = 0.02,
            c = 0.5,
            m = 0.5,
            N0 = 20,
            P0 = 30,
        ),
    )
    stop = 20u"yr"
    r = simulate(LotkaVolterra; config, stop)
    @test r.t[end] >= stop
    visualize(r, :t, [:N, :P], names=["prey", "predator"]) |> println
end
