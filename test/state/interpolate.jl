@testset "interpolate" begin
    @testset "basic" begin
        @system SInterpolate(Controller) begin
            m => ([1 => 10, 2 => 20, 3 => 30]) ~ interpolate
            n(m) ~ interpolate(reverse)
            a(m) => m(2.5) ~ track
            b(n) => n(25) ~ track
       end
       s = instance(SInterpolate)
       @test s.a' == 25
       @test s.b' == 2.5
    end

    @testset "matrix" begin
        @system SInterpolateMatrix(Controller) begin
            m => ([1 10; 2 20; 3 30]) ~ interpolate
            n(m) ~ interpolate(reverse)
            a(m) => m(2.5) ~ track
            b(n) => n(25) ~ track
       end
       s = instance(SInterpolateMatrix)
       @test s.a' == 25
       @test s.b' == 2.5
    end

    @testset "config" begin
        @system SInterpolateConfig(Controller) begin
            m => ([1 => 10]) ~ interpolate(parameter)
            n(m) ~ interpolate(reverse)
            a(m) => m(2.5) ~ track
            b(n) => n(25) ~ track
       end
       o = configure(SInterpolateConfig => (:m => [1 => 10, 2 => 20, 3 => 30]))
       s = instance(SInterpolateConfig; config=o)
       @test s.a' == 25
       @test s.b' == 2.5
    end

    @testset "unit" begin
        @system SInterpolateUnit(Controller) begin
            m => ([1 => 10, 2 => 20, 3 => 30]) ~ interpolate(u"s", knotunit=u"m")
            n(m) ~ interpolate(u"m", reverse)
            a(m) => m(2.5u"m") ~ track(u"s")
            b(n) => n(25u"s") ~ track(u"m")
       end
       s = instance(SInterpolateUnit)
       @test s.a' == 25u"s"
       @test s.b' == 2.5u"m"
    end
end
