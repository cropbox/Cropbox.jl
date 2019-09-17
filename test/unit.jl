using Unitful

@testset "unit" begin
    @testset "unit" begin
        @system SUnit begin
            a => 2 ~ track(u"m")
            b => 1 ~ track(u"s")
            c(a, b) => a / b ~ track(u"m/s")
        end
        s = instance(SUnit)
        @test s.a == 2u"m" && s.b == 1u"s" && s.c == 2u"m/s"
    end

    @testset "nounit" begin
        @system SNounit begin
            a => 1 ~ track(u"m")
            b(a) => ustrip(a) ~ track
        end
        s = instance(SNounit)
        @test s.a == u"1m"
        @test s.b == 1
    end

    @testset "nounit with alias" begin
        @system SNounitAlias begin
            a: aa => 1 ~ track(u"m")
            b(aa): bb => ustrip(aa) ~ track
        end
        s = instance(SNounitAlias)
        @test s.aa == u"1m"
        @test s.bb == 1
    end

    @testset "nounit with call" begin
        @system SNounitCall begin
            a => 1 ~ track(u"m")
            b(a; x) => (ustrip(a) + x) ~ call
            c(b) => b(1) ~ track
        end
        s = instance(SNounitCall)
        @test s.a == u"1m"
        @test Cropbox.value(s.b)(1) == 2
        @test s.c == 2
    end
end
