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
        @test s.a' == 1
        @test s.b' == 2
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
        @test s.a' == 1u"m"
        @test s.b' == 2u"m"
    end

    @testset "type and unit" begin
        @system SCallTypeUnit(Controller) begin
            fa(; x::Int(u"m")) => x ~ call::Int(u"m")
            a(fa) => fa(1u"m") ~ track::Int(u"m")
            fb(i; x::Int(u"m")) => i + x ~ call::Int(u"m")
            b(fb) => fb(1u"m") ~ track::Int(u"m")
            i => 1 ~ preserve::Int(u"m")
        end
        s = instance(SCallTypeUnit)
        @test s.a' == 1u"m"
        @test s.b' == 2u"m"
        @test s.a' |> Cropbox.deunitfy |> typeof == Int
        @test s.b' |> Cropbox.deunitfy |> typeof == Int
    end
end
