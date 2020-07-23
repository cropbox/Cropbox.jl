@testset "track" begin
    @testset "basic" begin
        @system STrack(Controller) begin
            a => 1 ~ track
            b => 2 ~ track
            c(a, b) => a + b ~ track
        end
        s = instance(STrack)
        @test s.a' == 1 && s.b' == 2 && s.c' == 3
    end

    @testset "cross reference" begin
        @test_throws LoadError @eval @system STrackXRef(Controller) begin
            a(b) => b ~ track
            b(a) => a ~ track
        end
    end

    @testset "minmax" begin
        @system STrackMinMax(Controller) begin
            a => 0 ~ track(min=1)
            b => 0 ~ track(max=2)
            c => 0 ~ track(min=1, max=2)
        end
        s = instance(STrackMinMax)
        @test s.a' == 1
        @test s.b' == 0
        @test s.c' == 1
    end

    @testset "minmax unit" begin
        @system STrackMinMaxUnit(Controller) begin
            a => 0 ~ track(u"m", min=1)
            b => 0 ~ track(u"m", max=2u"cm")
            c => 0 ~ track(u"m", min=1u"cm", max=2)
        end
        s = instance(STrackMinMaxUnit)
        @test s.a' == 1u"m"
        @test s.b' == 0u"m"
        @test s.c' == 1u"cm"
    end
end
