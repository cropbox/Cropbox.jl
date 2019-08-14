using Unitful

@testset "unit" begin
    @testset "unit" begin
        @system S begin
            a => 2u"m" ~ track(u"m")
            b => 1u"s" ~ track(u"s")
            c(a, b) => a / b ~ track(u"m/s")
        end
        s = instance(S)
        @test s.a == 2u"m" && s.b == 1u"s" && s.c == 2u"m/s"
    end
end
