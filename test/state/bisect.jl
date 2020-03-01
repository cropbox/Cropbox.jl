@testset "bisect" begin
    @testset "basic" begin
        @system SBisect(Controller) begin
            x(x) => 2x - 1 ~ bisect(lower=0, upper=2)
        end
        s = instance(SBisect)
        @test s.x' == 1
    end

    # @testset "order0" begin
    #     @system SolveOrder0 begin
    #         x(x) => ((x^2 + 1) / 2) ~ solve
    #     end
    #     s = instance(SolveOrder0)
    #     @test isapprox(s.x', 1; atol=1e-3)
    # end

    @testset "bisect with unit" begin
        @system SBisectUnit(Controller) begin
            x(x) => 2x - u"1m" ~ bisect(lower=u"0m", upper=u"2m", u"m")
        end
        s = instance(SBisectUnit)
        @test s.x' == u"1m"
    end
end
