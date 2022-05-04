@testset "bring" begin
    @testset "basic" begin
        @system SBringPart begin
            a ~ preserve(parameter)
            b(a) => 2a ~ track
            c(b) ~ accumulate
        end
        @eval @system SBring(Controller) begin
            p(context) ~ bring::SBringPart
        end
        o = SBringPart => :a => 1
        s = instance(SBring; config=o)
        @test s.a' == s.p.a' == 1
        @test s.b' == s.p.b' == 2
        @test_throws ErrorException s.c'
        @test s.p.c' == 0
        update!(s)
        @test_throws ErrorException s.c'
        @test s.p.c' == 2
    end

    @testset "override" begin
        @system SBringOverridePart begin
            a ~ preserve(parameter)
            b(a) => 2a ~ track
            c(b) ~ accumulate
        end
        @eval @system SBringOverrideMod begin
            p ~ bring::SBringOverridePart(override)
        end
        @eval @system SBringOverride(Controller) begin
            p(context) ~ ::SBringOverridePart
            m(context, p) ~ ::SBringOverrideMod
        end
        o = SBringOverridePart => :a => 1
        s = instance(SBringOverride; config=o)
        @test s.p === s.m.p
        @test s.m.a' == s.p.a' == 1
        @test s.m.b' == s.p.b' == 2
        @test_throws ErrorException s.m.c'
        @test s.p.c' == 0
        update!(s)
        @test_throws ErrorException s.m.c'
        @test s.p.c' == 2
    end

    @testset "parameters" begin
        @system SBringParamsPart begin
            a => 1 ~ preserve
            b(a) => 2a ~ track
            c(b) ~ accumulate
            d => true ~ flag
        end
        @eval @system SBringParams(Controller) begin
            p(context) ~ bring::SBringParamsPart(parameters)
        end
        #TODO: support system-based configuration for implicitly generated parameters
        o = :SBringParams => (;
            a = 0,
            b = 1,
            c = 2,
            d = false,
        )
        s = instance(SBringParams; config=o)
        @test s.a' == 0
        @test s.b' == 1
        @test_throws ErrorException s.c' == 2
        @test s.d' == false
        @test s.p.a' == 1
        @test s.p.b' == 2
        @test s.p.c' == 0
        @test s.p.d' == true
    end
end
