@testset "derive" begin
    @testset "basic" begin
        @system SDerive(Controller) begin
            a => 1 ~ track
            b => 2 ~ track
            c(a, b) => a + b ~ track
        end
        s = instance(SDerive)
        @test s.a' == 1 && s.b' == 2 && s.c' == 3
    end

    @testset "cross reference" begin
        @test_throws LoadError @eval @system SDeriveXRef(Controller) begin
            a(b) => b ~ track
            b(a) => a ~ track
        end
    end
end
