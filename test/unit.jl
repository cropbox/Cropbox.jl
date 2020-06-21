using DataFrames
import Unitful

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

    @testset "nothing" begin
        @test Cropbox.unitfy(nothing, u"m") === nothing
        @test Cropbox.unitfy(nothing, nothing) === nothing
    end

    @testset "missing" begin
        @test Cropbox.unitfy(missing, u"m") === missing
        @test Cropbox.unitfy(missing, nothing) === missing
    end

    @testset "nothing units" begin
        @test Cropbox.unitfy(1, nothing) === 1
        @test Cropbox.unitfy(1u"cm", nothing) === 1u"cm"
    end

    @testset "single" begin
        @test Cropbox.unitfy(1, u"m") === 1u"m"
        @test Cropbox.unitfy(1.0, u"m") === 1.0u"m"
        @test Cropbox.unitfy(1u"m", u"cm") === 100u"cm"
        @test Cropbox.unitfy(1.0u"m", u"cm") === 100.0u"cm"
    end

    @testset "percent" begin
        @test Cropbox.unitfy(1, u"percent") === 1u"percent"
        @test 1 |> u"percent" === 100u"percent"
        @test Cropbox.unitfy(1u"percent", nothing) === 1u"percent"
        @test Cropbox.unitfy(1u"percent", u"NoUnits") === 1//100
    end

    @testset "array" begin
        @test Cropbox.unitfy([1, 2, 3], u"m") == [1, 2, 3]u"m"
        @test Cropbox.unitfy([1, 2, 3]u"m", u"cm") == [100, 200, 300]u"cm"
        @test Cropbox.unitfy([1u"cm", 0.02u"m", 30u"mm"], u"cm") == [1, 2, 3]u"cm"
    end

    @testset "tuple" begin
        @test Cropbox.unitfy((1, 2, 3), u"m") === (1u"m", 2u"m", 3u"m")
        @test Cropbox.unitfy((1u"m", 2u"m", 3u"m"), u"cm") === (100u"cm", 200u"cm", 300u"cm")
        @test Cropbox.unitfy((1u"cm", 0.02u"m", 30u"mm"), u"cm") === (1u"cm", 2.0u"cm", 3//1*u"cm")
    end

    @testset "deunitfy" begin
        @test Cropbox.deunitfy(1) == 1
        @test Cropbox.deunitfy(1u"m") == 1
        @test Cropbox.deunitfy([1, 2, 3]u"m") == [1, 2, 3]
        @test Cropbox.deunitfy((1u"m", 2u"cm", 3)) === (1, 2, 3)
    end

    @testset "deunitfy with units" begin
        @test Cropbox.deunitfy(1, u"m") == 1
        @test Cropbox.deunitfy(1u"m", u"cm") == 100
        @test Cropbox.deunitfy([1, 2, 3]u"m", u"cm") == [100, 200, 300]
        @test Cropbox.deunitfy([1u"m", 2u"cm", 3u"mm"], u"mm") == [1000, 20, 3]
        @test_throws Unitful.DimensionError Cropbox.deunitfy([1u"m", 2u"cm", 3], u"mm")
        @test Cropbox.deunitfy((1u"m", 2u"cm", 3u"mm"), u"mm") === (1000, 20, 3)
        @test_throws Unitful.DimensionError Cropbox.deunitfy((1u"m", 2u"cm", 3), u"mm")
    end

    @testset "dataframe" begin
        df = DataFrame(a=[0], b=[0])
        U = [u"s", nothing]
        r = Cropbox.unitfy(df, U)
        @test Cropbox.unit(eltype(r[!, 1])) == u"s"
        @test Cropbox.unit(eltype(r[!, 2])) == u"NoUnits"
    end

    @testset "dataframe auto" begin
        df = DataFrame()
        z = [0]
        df."a (g/cm^2)" = z
        df."c (a)(b)(s)" = z
        df."b ()" = z
        df."d" = z
        r = Cropbox.unitfy(df)
        @test Cropbox.unit(eltype(r[!, 1])) == u"g/cm^2"
        @test Cropbox.unit(eltype(r[!, 2])) == u"s"
        @test Cropbox.unit(eltype(r[!, 3])) == u"NoUnits"
        @test Cropbox.unit(eltype(r[!, 4])) == u"NoUnits"
        N = names(r)
        @test N[1] == "a"
        @test N[2] == "c (a)(b)"
        @test N[3] == "b ()"
        @test N[4] == "d"
    end
end
