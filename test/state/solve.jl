@testset "solve" begin
    @testset "bisect" begin
        @system SolveBisect(Controller) begin
            x(x) => 2x - 1 ~ solve(lower=0, upper=2)
        end
        s = instance(SolveBisect)
        @test s.x == 1
    end

    # @testset "order0" begin
    #     @system SolveOrder0 begin
    #         x(x) => ((x^2 + 1) / 2) ~ solve
    #     end
    #     s = instance(SolveOrder0)
    #     @test isapprox(s.x', 1; atol=1e-3)
    # end

    @testset "bisect with unit" begin
        @system SolveBisectUnit(Controller) begin
            x(x) => 2x - u"1m" ~ solve(lower=u"0m", upper=u"2m", u"m")
        end
        s = instance(SolveBisectUnit)
        @test s.x == u"1m"
    end
end
