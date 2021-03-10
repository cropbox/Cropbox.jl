@testset "flag" begin
    @testset "basic" begin
        @system SFlag(Controller) begin
            a => true ~ flag
            b => false ~ flag
        end
        s = instance(SFlag)
        @test s.a' == true && s.b' == false
    end

    @testset "flag vs track" begin
        @system SFlagVsTrack(Controller) begin
            a => 1 ~ accumulate
            f1(a) => a >= 1 ~ flag(lazy)
            f2(a) => a >= 1 ~ flag
            f3(a) => a >= 1 ~ track::Bool
            x1(f1) => (f1 ? 1 : 0) ~ track
            x2(f2) => (f2 ? 1 : 0) ~ track
            x3(f3) => (f3 ? 1 : 0) ~ track
        end
        s = instance(SFlagVsTrack)
        @test s.a' == 0
        @test s.f1' == false && s.f2' == false && s.f3' == false
        @test s.x1' == 0 && s.x2' == 0 && s.x3' == 0
        update!(s)
        @test s.a' == 1
        @test s.f1' == true && s.f2' == true && s.f3' == true
        @test s.x1' == 0 && s.x2' == 1 && s.x3' == 1
        update!(s)
        @test s.a' == 2
        @test s.f1' == true && s.f2' == true && s.f3' == true
        @test s.x1' == 1 && s.x2' == 1 && s.x3' == 1
    end
end
