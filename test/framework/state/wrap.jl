@testset "wrap" begin
    @testset "basic" begin
        @system SWrap(Controller) begin
            a => 1 ~ preserve
            b(a) => 2a ~ track
            c(wrap(a)) => 2a' ~ track
        end
        s = instance(SWrap)
        @test s.b' == s.c' == 2
    end
end
