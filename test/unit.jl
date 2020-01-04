using Unitful

@testset "unit" begin
    @testset "unit" begin
        @system SUnit(Controller) begin
            a => 2 ~ track(u"m")
            b => 1 ~ track(u"s")
            c(a, b) => a / b ~ track(u"m/s")
        end
        s = instance(SUnit)
        @test s.a' == 2u"m" && s.b' == 1u"s" && s.c' == 2u"m/s"
    end

    @testset "unitless" begin
        @system SUnitless(Controller) begin
            a => 200 ~ track(u"cm^2")
            b => 10 ~ track(u"m^2")
            c(a, b) => a / b ~ track(u"cm^2/m^2")
            d(a, b) => a / b ~ track(u"m^2/m^2")
            e(a, b) => a / b ~ track
        end
        s = instance(SUnitless)
        @test s.a' == 200u"cm^2"
        @test s.b' == 10u"m^2"
        @test s.c' == 20u"cm^2/m^2"
        @test s.d' == 0.002
        @test s.e' == 0.002
    end

    @testset "nounit" begin
        @system SNounit(Controller) begin
            a => 1 ~ track(u"m")
            b(nounit(a)) ~ track
        end
        s = instance(SNounit)
        @test s.a' == u"1m"
        @test s.b' == 1
    end

    @testset "nounit with alias" begin
        @system SNounitAlias(Controller) begin
            a: aa => 1 ~ track(u"m")
            b(nounit(aa)): bb ~ track
        end
        s = instance(SNounitAlias)
        @test s.aa' == u"1m"
        @test s.bb' == 1
    end

    @testset "nounit with call" begin
        @system SNounitCall(Controller) begin
            a => 1 ~ track(u"m")
            b(nounit(a); x) => (a + x) ~ call
            c(b) => b(1) ~ track
        end
        s = instance(SNounitCall)
        @test s.a' == u"1m"
        @test s.b'(1) == 2
        @test s.c' == 2
    end
    
    @testset "nounit nested" begin
        @system SNounitNestedComponent begin
            a => 1 ~ track(u"m")
        end
        @system SNounitNested(Controller) begin
            n(context) ~ ::SNounitNestedComponent
            a(n.a) ~ track(u"m")
            b(nounit(n.a)) ~ track
            c(x=nounit(n.a)) => 2x ~ track
        end
        s = instance(SNounitNested)
        @test s.n.a' == s.a' == u"1m"
        @test s.b' == 1
        @test s.c' == 2
    end
end
