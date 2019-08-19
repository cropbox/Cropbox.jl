@testset "lotka volterra" begin
    @system S begin
        timestep(t="context.clock.tick"): t => 0.01t ~ track
        prey_birth_rate: a => 1.0 ~ track
        prey_death_rate: b => 0.1 ~ track
        predator_death_rate: c => 1.5 ~ track
        predator_reproduction_rate: d => 0.75 ~ track
        prey_initial_population: H0 => 10 ~ track
        predator_initial_population: P0 => 5 ~ track
        prey_population(a, b, H, P): H => a*H - b*H*P ~ accumulate(init="H0", time="t")
        predator_population(b, c, d, H, P): P => d*b*H*P - c*P ~ accumulate(init="P0", time="t")
    end
    s = instance(S)
    T = Float64[]
    H = Float64[]
    P = Float64[]
    #TODO: isless() for Var with proper promote_rule
    while value(s.t) <= 20.0
        #println("t = $(s.t): H = $(s.H), P = $(s.P)")
        push!(T, value(s.t))
        push!(H, value(s.H))
        push!(P, value(s.P))
        advance!(s)
    end
    @test value(s.t) > 20.0
    using Plots
    unicodeplots()
    plot(T, [H P], lab=["Prey" "Predator"], xlab="Time", ylab="Population", xlim=(0, T[end]), ylim=(0, ceil(maximum([H P]))))
end
