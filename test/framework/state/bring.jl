@testset "bring" begin
    @testset "basic" begin
        @system SBringPart begin
            a ~ preserve(parameter)
            b(a) => 2a ~ track
            c(b) ~ accumulate
        end
        @eval @system SBring(SBringPart, Controller) begin
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
        @eval @system SBringOverrideMod(SBringOverridePart) begin
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

    @testset "mixin" begin
        @system SBringMixinPart begin
            a => 1 ~ preserve
        end
        @test_throws LoadError @eval @system SBringMixin(Controller) begin
            p(context) ~ bring::SBringMixinPart
        end
    end
end
