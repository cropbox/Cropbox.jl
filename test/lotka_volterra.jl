@testset "lotka volterra" begin
    @system S begin
        prey_birth_rate: a => 1.0 ~ track
        prey_death_rate: b => 0.1 ~ track
        predator_death_rate: c => 1.5 ~ track
        predator_reproduction_rate: d => 0.75 ~ track
        prey_initial_population: H0 => 10 ~ track
        predator_initial_population: P0 => 5 ~ track
        prey_population(a, b, H, P): H => a*H - b*H*P ~ accumulate(init="H0")
        predator_population(b, c, d, H, P): P => d*b*H*P - c*P ~ accumulate(init="P0")
    end
    s = instance(S, Dict(:Clock => Dict(:interval => 0.01)))
end
