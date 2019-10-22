@testset "macro" begin
    @testset "alias" begin
        @system SAlias(Controller) begin
            a: aa => 1 ~ track
            b: [bb, bbb] => 2 ~ track
            c(a, aa, b, bb, bbb) => a + aa + b + bb + bbb ~ track
        end
        s = instance(SAlias)
        @test s.a == 1 == s.aa
        @test s.b == 2 == s.bb == 2 == s.bbb
        @test s.c == 8
    end

    @testset "single arg without key" begin
        @system SSingleArgWithoutKey(Controller) begin
            a => 1 ~ track
            b(a) ~ track
            c(x=a) ~ track
        end
        s = instance(SSingleArgWithoutKey)
        @test s.a == 1
        @test s.b == 1
        @test s.c == 1
    end
end
