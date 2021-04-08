@testset "core" begin
    @testset "name" begin
        @system SSystemName(Controller)
        s = instance(SSystemName)
        @test Cropbox.namefor(s) == :SSystemName
        @test Cropbox.namefor(SSystemName) == :SSystemName
        S = typeof(s)
        @test startswith(string(S), "var\"##SSystemName#")
        @test S <: SSystemName
        @test Cropbox.namefor(S) == :SSystemName
    end

    @testset "names" begin
        @test names(System) == [:System]
        @test names(Controller) == [:Controller]
        @test names(Context) == [:Context]
        @test names(Clock) == [:Clock]
    end

    @testset "iteration" begin
        @system SSystemCollect(Controller) begin
            a => 1 ~ preserve
            b(a) => 2a ~ track
        end
        s = instance(SSystemCollect)
        @test length(s) == 4
        @test collect(s) == [s.context, s.config, s.a, s.b]
        @test s[:a] == s.a
        @test s["a"] == s.a
        @test s."a" == s.a
        @test s["context.clock"] == s.context.clock
        @test s."context.clock" == s.context.clock
        @test s[nothing] == s
        @test s[""] == s
    end

    @testset "setvar!" begin
        @system SSystemSetVar(Controller) begin
            a => 1 ~ preserve
            b => 2 ~ preserve
        end
        s = instance(SSystemSetVar)
        @test s.a' == 1 && s.b' == 2
        a, b = s.a, s.b
        Cropbox.setvar!(s, :b, a)
        Cropbox.setvar!(s, :a, b)
        @test s.a === b && s.b === a
        @test s.a' == 2 && s.b' == 1
    end

    @testset "value" begin
        @system SSystemValue(Controller) begin
            a => 1 ~ preserve
            b(a) => 2a ~ preserve
            c(a, b) => a + b ~ track
            d(c) ~ accumulate
        end
        s = instance(SSystemValue)
        @test s.a' == 1 && s.b' == 2 && s.c' == 3
        @test Cropbox.value(s, :b; a=2) == 4
        @test Cropbox.value(s, :c; a=0, b=1) == 1
        @test_throws ErrorException Cropbox.value(s, :c; a=0)
        @test_throws AssertionError Cropbox.value(s, :d; c=0)
    end
end
