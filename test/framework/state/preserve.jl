@testset "preserve" begin
    @testset "basic" begin
        @system SPreserve(Controller) begin
            a => 1 ~ track
            b(a) => a + 1 ~ accumulate
            c(b) => b ~ preserve
        end
        s = instance(SPreserve)
        @test s.a' == 1 && s.b' == 0 && s.c' == 0
        update!(s)
        @test s.a' == 1 && s.b' == 2 && s.c' == 0
    end

    @testset "optional" begin
        @system SPreserveOptional(Controller) begin
            a ~ preserve(optional)
            b => 1 ~ preserve(optional)
        end
        s = instance(SPreserveOptional)
        @test isnothing(s.a') && s.b' == 1
        update!(s)
        @test isnothing(s.a') && s.b' == 1
    end

    @testset "parameter" begin
        @system SParameter(Controller) begin
            a => 1 ~ preserve(parameter)
        end
        s = instance(SParameter)
        @test s.a' == 1
        update!(s)
        @test s.a' == 1
    end

    @testset "parameter with config" begin
        @system SParameterConfig(Controller) begin
            a => 1 ~ preserve(parameter)
        end
        o = SParameterConfig => :a => 2
        s = instance(SParameterConfig; config=o)
        @test s.a' == 2
    end

    @testset "parameter with config alias" begin
        @system SParameterConfigAlias(Controller) begin
            a: aa => 1 ~ preserve(parameter)
            bb: b => 1 ~ preserve(parameter)
        end
        o = SParameterConfigAlias => (:a => 2, :b => 2)
        s = instance(SParameterConfigAlias; config=o)
        @test s.a' == 2
        @test s.b' == 2
    end
    
    @testset "parameter missing" begin
        @system SParameterMissing(Controller) begin
            a => 1 ~ preserve(parameter)
        end
        o = SParameterMissing => :a => missing
        s = instance(SParameterMissing; config=o)
        @test s.a' == 1
    end

    @testset "parameter nothing" begin
        @system SParameterNothing(Controller) begin
            a => 1 ~ preserve(parameter, optional)
        end
        o = SParameterNothing => :a => nothing
        s = instance(SParameterNothing; config=o)
        @test s.a' === nothing
    end

    @testset "minmax" begin
        @system SPreserveMinMax(Controller) begin
            a => 0 ~ preserve(parameter, min=1)
            b => 0 ~ preserve(parameter, max=2)
            c => 0 ~ preserve(parameter, min=1, max=2)
        end
        s = instance(SPreserveMinMax)
        @test s.a' == 1
        @test s.b' == 0
        @test s.c' == 1
    end
        
    @testset "parameter minmax" begin
        @system SParameterMinMax(Controller) begin
            a => 0 ~ preserve(parameter, min=-1)
            b => 0 ~ preserve(parameter, max=1)
            c => 0 ~ preserve(parameter, min=-1, max=1)
        end
        o1 = SParameterMinMax => (:a => 2, :b => 2, :c => 2)
        s1 = instance(SParameterMinMax; config=o1)
        @test s1.a' == 2
        @test s1.b' == 1
        @test s1.c' == 1
        o2 = SParameterMinMax => (:a => -2, :b => -2, :c => -2)
        s2 = instance(SParameterMinMax; config=o2)
        @test s2.a' == -1
        @test s2.b' == -2
        @test s2.c' == -1
    end

    @testset "round" begin
        @system SPreserveRound(Controller) begin
            a => 1.4 ~ preserve(round)
            b => 1.4 ~ preserve(round=:round)
            c => 1.4 ~ preserve(round=:ceil)
            d => 1.4 ~ preserve(round=:floor)
            e => 1.4 ~ preserve(round=:trunc)
        end
        s = instance(SPreserveRound)
        @test s.a' === s.b'
        @test s.b' === 1.0
        @test s.c' === 2.0
        @test s.d' === 1.0
        @test s.e' === 1.0
    end

    @testset "parameter round" begin
        @system SParameterRound(Controller) begin
            a ~ preserve::int(parameter, round=:floor)
            b ~ preserve::int(parameter, round=:trunc)
        end
        o1 = :0 => (a = 1.4, b = 1.4)
        s1 = instance(SParameterRound; config=o1)
        @test s1.a' === 1
        @test s1.b' === 1
        o2 = :0 => (a = -1.4, b = -1.4)
        s2 = instance(SParameterRound; config=o2)
        @test s2.a' === -2
        @test s2.b' === -1
    end
end
