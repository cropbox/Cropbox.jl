@testset "macro" begin
    @testset "alias" begin
        @system SAlias(Controller) begin
            a: aa => 1 ~ track
            b: [bb, bbb] => 2 ~ track
            c(a, aa, b, bb, bbb) => a + aa + b + bb + bbb ~ track
        end
        s = instance(SAlias)
        @test s.a' == s.aa' == 1
        @test s.b' == s.bb' == s.bbb' == 2
        @test s.c' == 8
    end

    @testset "single arg without key" begin
        @system SSingleArgWithoutKey(Controller) begin
            a => 1 ~ track
            b(a) ~ track
            c(x=a) ~ track
        end
        s = instance(SSingleArgWithoutKey)
        @test s.a' == 1
        @test s.b' == 1
        @test s.c' == 1
    end
    
    @testset "body replacement" begin
        @system SBodyReplacement1(Controller) begin
            a => 1 ~ preserve
        end
        @eval @system SBodyReplacement2(SBodyReplacement1) begin
            a => 2
        end
        s1 = instance(SBodyReplacement1)
        s2 = instance(SBodyReplacement2)
        @test s1.a' == 1
        @test s2.a' == 2
    end
end
