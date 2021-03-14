@testset "remember" begin
    @testset "basic" begin
        @system SRemember(Controller) begin
            t(nounit(context.clock.time)) ~ track
            w(t) => t >= 2 ~ flag
            i => -1 ~ preserve
            r(t) ~ remember(init=i, when=w)
        end
        s = instance(SRemember)
        @test !s.w'
        @test s.r' == s.i'
        update!(s)
        @test !s.w'
        @test s.r' == s.i'
        update!(s)
        @test s.w'
        @test s.r' == s.t'
        t = s.t'
        update!(s)
        @test s.w'
        @test s.r' != s.t' && s.r' == t
    end
end
