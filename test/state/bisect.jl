@testset "bisect" begin
    @testset "basic" begin
        @system SBisect(Controller) begin
            x(x) => x - 1 ~ bisect(lower=0, upper=2)
        end
        s = instance(SBisect)
        @test s.x' == 1
    end

    @testset "unit" begin
        @system SBisectUnit(Controller) begin
            x(x) => x - u"1m" ~ bisect(lower=u"0m", upper=u"2m", u"m")
        end
        s = instance(SBisectUnit)
        @test s.x' == u"1m"
    end

    @testset "eval unit" begin
        @system SBisectEvalUnit(Controller) begin
            f(x) => (x/1u"s" - 1u"m/s") ~ track(u"m/s")
            x(f) ~ bisect(lower=0, upper=2, u"m", evalunit=u"m/s")
        end
        s = instance(SBisectEvalUnit)
        @test s.x' == 1u"m"
        @test Cropbox.unit(s.x) == u"m"
        @test Cropbox.evalunit(s.x) == u"m/s"
    end

    @testset "equal" begin
        @system SBisectEqual(Controller) begin
            x1(x1) => (x1 - 1) ~ bisect(lower=0, upper=2)
            x2(x2) => (x2 - 1 ⩵ 0) ~ bisect(lower=0, upper=2)
        end
        s = instance(SBisectEqual)
        @test s.x1' == s.x2'
    end
end
