@testset "flag" begin
    @testset "basic" begin
        @system SFlag(Controller) begin
            a => true ~ flag
            b => false ~ flag
        end
        s = instance(SFlag)
        @test s.a' == true && s.b' == false
    end

    @testset "flag vs track" begin
        @system SFlagVsTrack(Controller) begin
            a => 1 ~ accumulate
            f1(a) => a >= 1 ~ flag
            f2(a) => a >= 1 ~ track::Bool
            x1(f1) => (f1 ? 1 : 0) ~ track
            x2(f2) => (f2 ? 1 : 0) ~ track
        end
        s = instance(SFlagVsTrack)
        @test s.a' == 0
        @test s.f1' == false && s.f2' == false
        @test s.x1' == 0 && s.x2' == 0
        update!(s)
        @test s.a' == 1
        @test s.f1' == true && s.f2' == true
        @test s.x1' == 1 && s.x2' == 1
        update!(s)
        @test s.a' == 2
        @test s.f1' == true && s.f2' == true
        @test s.x1' == 1 && s.x2' == 1
    end

    @testset "flag parameter" begin
        @system SFlagParameter(Controller) begin
            a => true ~ flag(parameter)
            b => false ~ flag(parameter)
            c => true ~ flag(parameter, when = false)
        end
        s1 = instance(SFlagParameter)
        @test s1.a' == true && s1.b' == false
        @test s1.c'
        update!(s1)
        @test s1.c'
        c = :SFlagParameter => (a = false, b = true, c = false)
        s2 = instance(SFlagParameter; config=c)
        @test s2.a' == false && s2.b' == true
        @test !s2.c'
        update!(s2)
        @test !s2.c'
    end

    @testset "override" begin
        @system SFlagOverridePart begin
            a ~ flag(override, once, when = false)
        end
        @system SFlagOverride(Controller) begin
            child(context, a) ~ ::SFlagOverridePart
            a(t = context.clock.tick) => isodd(t) ~ flag
        end
        s = instance(SFlagOverride)
        @test s.a === s.child.a
        for i in 0:2
            i > 0 && update!(s)
            @test s.child.a' == isodd(i)
        end
    end

    @testset "when and once" begin
        @system SFlagConditions(Controller) begin
            enabled(t = context.clock.tick) => t in (1, 3, 4, 6) ~ flag
            condition(t = context.clock.tick) => t in (2, 3, 5, 6) ~ flag
            current(enabled, condition) => begin
                enabled || error("disabled flag body")
                condition
            end ~ flag(when = enabled)
            latched(t = context.clock.tick, enabled, condition) => begin
                enabled && t <= 3 || error("disabled or latched flag body")
                condition
            end ~ flag(once, when = enabled)
            ungated(t = context.clock.tick, condition) => begin
                t <= 2 || error("latched flag body")
                condition
            end ~ flag(once)
            tracked(condition) ~ track::Bool(when = enabled)
            remembered(condition) ~ remember::Bool(when = enabled)
            valid(latched) => !latched ~ flag
        end
        expected = [
            (false, false, false),
            (false, false, false),
            (false, false, true),
            (true, true, true),
            (false, true, true),
            (false, true, true),
            (true, true, true),
        ]
        s = instance(SFlagConditions)
        for (i, (current, latched, ungated)) in enumerate(expected)
            i > 1 && update!(s)
            @test (s.current', s.latched', s.ungated') == (current, latched, ungated)
            @test (s.tracked', s.valid', s.remembered') == (current, !latched, false)
        end
        fresh = instance(SFlagConditions)
        @test (fresh.current', fresh.latched', fresh.ungated') == first(expected)
    end

    @testset "literal conditions" begin
        @system SFlagLiteralConditions(Controller) begin
            a => true ~ flag(when = true)
            b => error("disabled flag body") ~ flag(when = false)
            c(t = context.clock.tick) => t == 0 || error("latched flag body") ~ flag(once, when = true)
            d => error("disabled flag body") ~ flag(once, when = false)
        end
        s = instance(SFlagLiteralConditions)
        for i in 0:2
            i > 0 && update!(s)
            @test (s.a', s.b', s.c', s.d') == (true, false, true, false)
        end
    end

    @testset "no init" for init in (false, true)
        @test_throws r"unsupported tag: init" @eval @system SFlagInit begin
            a => true ~ flag(init = $init)
        end
    end
end
