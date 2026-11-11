using TimeZones

@testset "call" begin
    @testset "basic" begin
        @system SCall(Controller) begin
            fa(; x) => x ~ call
            a(fa) => fa(1) ~ track
            fb(i; x) => i + x ~ call
            b(fb) => fb(1) ~ track
            i => 1 ~ preserve
        end
        s = instance(SCall)
        @test s.a' === 1.0
        @test s.b' === 2.0
    end

    @testset "unit" begin
        @system SCallUnit(Controller) begin
            fa(; x(u"m")) => x ~ call(u"m")
            a(fa) => fa(1u"m") ~ track(u"m")
            fb(i; x(u"m")) => i + x ~ call(u"m")
            b(fb) => fb(1u"m") ~ track(u"m")
            i => 1 ~ preserve(u"m")
        end
        s = instance(SCallUnit)
        @test s.a' === 1.0u"m"
        @test s.b' === 2.0u"m"
    end

    @testset "type and unit" begin
        @system SCallTypeUnit(Controller) begin
            fa(; x::Int(u"m")) => x ~ call::int(u"m")
            a(fa) => fa(1u"m") ~ track::int(u"m")
            fb(i; x::Int(u"m")) => i + x ~ call::int(u"m")
            b(fb) => fb(1u"m") ~ track::int(u"m")
            i => 1 ~ preserve::int(u"m")
        end
        s = instance(SCallTypeUnit)
        @test s.a' === 1u"m"
        @test s.b' === 2u"m"
        @test s.a' |> Cropbox.deunitfy isa Int
        @test s.b' |> Cropbox.deunitfy isa Int
    end

    @testset "local wrapper" begin
        f(x) = Cropbox.FunctionWrapper{Float64,Tuple{Float64}}(y -> y - x)(2x)
        @test f(1.5) === 1.5
    end

    @testset "deepcopy" begin
        @system SCallCopy(Controller) begin
            a       => 1     ~ accumulate
            f(a; x) => a + x ~ call
        end
        s = instance(SCallCopy)
        t = deepcopy(s)
        update!(t)
        @test t.f(1) == 2
        @test s.f(1) == 1
    end

    @testset "non-isbits argument and return" begin
        @system SCallDate(Controller) begin
            f(; x::ZonedDateTime) => x ~ call::ZonedDateTime
        end
        s = instance(SCallDate)
        t = ZonedDateTime(2020, 1, 1, tz"UTC")
        @test s.f(t) == t
    end
end
