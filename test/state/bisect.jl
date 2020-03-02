@testset "bisect" begin
    @testset "basic" begin
        @system SBisect(Controller) begin
            x(x) => 2x - 1 ~ bisect(lower=0, upper=2)
        end
        s = instance(SBisect)
        @test s.x' == 1
    end

    @testset "bisect with unit" begin
        @system SBisectUnit(Controller) begin
            x(x) => 2x - u"1m" ~ bisect(lower=u"0m", upper=u"2m", u"m")
        end
        s = instance(SBisectUnit)
        @test s.x' == u"1m"
    end
end
