@testset "controller" begin
    @testset "options" begin
        @system SControllerOptions(Controller) begin
            a ~ preserve(extern)
            b ~ ::int(override)
        end
        o = (a=1, b=2)
        s = instance(SControllerOptions; options=o)
        @test s.a' == 1
        @test s.b == 2
    end

    @testset "config placeholder" begin
        @system SControllerConfigPlaceholder(Controller) begin
            a => 1 ~ preserve(parameter)
        end
        o = 0 => :a => 2
        s = instance(SControllerConfigPlaceholder; config=o)
        @test s.a' == 2
    end

    @testset "seed" begin
        @system SControllerSeed(Controller) begin
            a => 0 ± 1 ~ preserve
        end
        s1 = instance(SControllerSeed; seed=0)
        @test s1.a' == 0.6791074260357777
        s2 = instance(SControllerSeed; seed=0)
        @test s1.a' == s2.a'
    end

    @testset "no seed" begin
        @system SControllerNoSeed(Controller) begin
            a => 0 ± 1 ~ preserve
        end
        s1 = instance(SControllerNoSeed; seed=nothing)
        s2 = instance(SControllerNoSeed; seed=nothing)
        @test s1.a' != s2.a'
    end
end
