@testset "lotka volterra" begin
    @system LotkaVolterra(Controller) begin
        prey_birth_rate: a => 1.0 ~ track(u"hr^-1")
        prey_death_rate: b => 0.1 ~ track(u"hr^-1")
        predator_death_rate: c => 1.5 ~ track(u"hr^-1")
        predator_reproduction_rate: d => 0.75 ~ track
        prey_initial_population: H0 => 10.0 ~ track
        predator_initial_population: P0 => 5.0 ~ track
        prey_population(a, b, H, P): H => a*H - b*H*P ~ accumulate(init=H0)
        predator_population(b, c, d, H, P): P => d*b*H*P - c*P ~ accumulate(init=P0)
    end
    s = instance(LotkaVolterra, config=(
        :Clock => (:step => 1u"minute"),
    ))
    T = Float64[]
    H = Float64[]
    P = Float64[]
    #TODO: isless() for Var with proper promote_rule
    t = s.context.clock.tick
    while t' <= 20.0u"hr"
        #println("t = $(s.t): H = $(s.H), P = $(s.P)")
        push!(T, t' |> ustrip)
        push!(H, s.H')
        push!(P, s.P')
        update!(s)
    end
    @test t' > 20.0u"hr"
    using Plots
    unicodeplots()
    plot(T, [H P], lab=["Prey" "Predator"], xlab="Time", ylab="Population", xlim=(0, T[end]), ylim=(0, ceil(maximum([H P]))))
end
