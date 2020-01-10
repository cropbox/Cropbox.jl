@testset "macro" begin
    @testset "alias" begin
        @system SAlias(Controller) begin
            a: aa => 1 ~ track
            b(a, aa) => a + aa ~ track
        end
        s = instance(SAlias)
        @test s.a' == s.aa' == 1
        @test s.b' == 2
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
        @test s1.a isa Cropbox.Preserve
        @test s1.a' == 1
        @test s2.a isa Cropbox.Preserve
        @test s2.a' == 2
    end

    @testset "replacement with different alias" begin
        @system SReplacementDifferentAlias1 begin
            x: aaa => 1 ~ preserve
        end
        @test_logs (:warn, "variable replaced with inconsistent alias") @eval @system SReplacementDifferentAlias2(SReplacementDifferentAlias1) begin
            x: bbb => 2 ~ preserve
        end
    end
    
    @testset "custom system" begin
        abstract type SAbstractCustomSystem <: System end
        @system SCustomSystem <: SAbstractCustomSystem
        @test SCustomSystem <: System
        @test SCustomSystem <: SAbstractCustomSystem
    end
end
