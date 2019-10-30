using DataFrames

@testset "util" begin
    @testset "run" begin
        @system SRun(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 10
        r = run!(SRun, n)
        @test typeof(r) <: DataFrame
        @test size(r, 1) == (n+1)
        @test names(r) == [:tick, :a, :b]
        @test r[end, :tick] == (n+1)u"hr"
        @test r[end, :a] == 1
        @test r[end, :b] == n
        r = run!(SRun, n, config=(:SRun => :a => 2))
        @test r[end, :a] == 2
        @test r[end, :b] == 2n
        r = run!(SRun, n, columns=[:b])
        @test size(r, 2) == 2
        @test names(r) == [:tick, :b]
        r = run!(SRun, n, index=:b, columns=[:b])
        @test size(r, 2) == 1
        @test names(r) == [:b]
    end

    @testset "fit" begin
        @system SFit(Controller) begin
            a => 0 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 10
        t, a, b = 10.0u"hr", 20, 180
        A = (0.0, 100.0)
        obs = DataFrame(tick=[t], b=[b])
        p = fit!(SFit, obs, n, column=:b, parameters=("SFit.a" => A))
        @test p[:SFit][:a] == a
        r = run!(SFit, n, config=p)
        @test r[r[!, :tick] .== t, :][1, :b] == b
    end
end
