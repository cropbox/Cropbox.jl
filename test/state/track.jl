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
    
    #TODO: implement min/max tags for track (should be done with genstore() in macro.jl)
    @testset "minmax" begin
        @system STrackMinMax(Controller) begin
            a => 0 ~ track(min=1)
            b => 0 ~ track(max=2)
            c => 0 ~ track(min=1, max=2)
        end
        s = instance(STrackMinMax)
        @test_skip s.a' == 1
        @test_skip s.b' == 0
        @test_skip s.c' == 1
    end
end
