@testset "preserve" begin
    @testset "basic" begin
        @system SPreserve(Controller) begin
            a => 1 ~ track
            b(a) => a + 1 ~ accumulate
            c(b) => b ~ preserve
        end
        s = instance(SPreserve)
        @test s.a == 1 && s.b == 0 && s.c == 0
        update!(s)
        @test s.a == 1 && s.b == 2 && s.c == 0
    end

    @testset "parameter" begin
        @system SParameter(Controller) begin
            a => 1 ~ preserve(parameter)
        end
        s = instance(SParameter)
        @test s.a == 1
        update!(s)
        @test s.a == 1
    end

    @testset "parameter with config" begin
        @system SParameterConfig(Controller) begin
            a => 1 ~ preserve(parameter)
        end
        o = configure(SParameterConfig => (:a => 2))
        s = instance(SParameterConfig; config=o)
        @test s.a == 2
    end

    @testset "parameter with config alias" begin
        @system SParameterConfigAlias(Controller) begin
            a: aa => 1 ~ preserve(parameter)
            bb: b => 1 ~ preserve(parameter)
        end
        o = configure(SParameterConfigAlias => (:a => 2, :b => 2))
        s = instance(SParameterConfigAlias; config=o)
        @test s.a == 2
        @test s.b == 2
    end
end
