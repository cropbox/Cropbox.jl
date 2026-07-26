@testset "clock" begin
    @testset "basic" begin
        @system SClock(Controller)
        s = instance(SClock)
        @test s.context.clock.init' isa Cropbox.Quantity{Rational{Int64}}
        @test s.context.clock.step' isa Cropbox.Quantity{Rational{Int64}}
        @test s.context.clock.time' isa Cropbox.Quantity{Rational{Int64}}
        @test s.context.clock.time' == 0u"hr"
        @test s.context.clock.tick' === 0
        update!(s)
        @test s.context.clock.time' == 1u"hr"
        @test s.context.clock.tick' === 1
        update!(s)
        @test s.context.clock.time' == 2u"hr"
        @test s.context.clock.tick' === 2
    end

    @testset "config" begin
        @system SClockConfig(Controller)
        o = :Clock => (#=:init => 5,=# :step => 10)
        s = instance(SClockConfig; config=o)
        @test s.context.clock.time' == 0u"hr"
        @test s.context.clock.tick' === 0
        update!(s)
        @test s.context.clock.time' == 10u"hr"
        @test s.context.clock.tick' === 1
        update!(s)
        @test s.context.clock.time' == 20u"hr"
        @test s.context.clock.tick' === 2
    end

    @testset "subhourly advance" begin
        @system SClockSubhourly(Controller)
        s = instance(SClockSubhourly; config=:Clock => (:step => 10u"minute"))
        @test s.context.clock.step' === (1//6)u"hr"
        for _ in 1:6
            update!(s)
        end
        @test s.context.clock.time' === (1//1)u"hr"
        @test s.context.clock.tick' === 6
    end

    @testset "floating-point step" begin
        @system SClockFloatInput(Controller)
        local whole
        @test_logs (:warn, r"floating-point value converted") whole = instance(
            SClockFloatInput;
            config=:Clock => (:step => 1.0u"minute"),
        )
        @test whole.context.clock.step' === (1//60)u"hr"
        local fractional
        @test_logs (:warn, r"floating-point value converted") fractional = instance(
            SClockFloatInput;
            config=:Clock => (:step => 0.1u"hr"),
        )
        @test fractional.context.clock.step' === (1//10)u"hr"
        @test_throws ArgumentError instance(
            SClockFloatInput;
            config=:Clock => (:step => Inf*u"hr"),
        )
    end

    @testset "nested clock" begin
        @system SSubhourlyClock(Clock) <: Clock begin
            step => 10u"minute" ~ preserve::rational(u"hr", parameter)
        end
        @system SSubhourlyContext(Context) <: Context begin
            context ~ ::Context(override)
            clock(config) ~ ::SSubhourlyClock
        end
        @system SSubhourlyChild begin
            context ~ ::SSubhourlyContext(override)
        end
        @system SSubhourlyParent(Controller) begin
            child_context(context, config) ~ ::SSubhourlyContext(context)
            child(context=child_context) ~ ::SSubhourlyChild
        end
        s = instance(SSubhourlyParent)
        update!(s)
        @test s.context.clock.time' === (1//1)u"hr"
        @test s.child.context.clock.time' === (1//1)u"hr"
        @test s.child.context.clock.tick' === 6
    end

    @testset "daily" begin
        @system SClockDaily{Context => Cropbox.DailyContext}(Controller) begin
            a => 1 ~ accumulate
        end
        s = instance(SClockDaily)
        @test s.context isa Cropbox.DailyContext
        @test s.context.clock isa Cropbox.DailyClock
        @test s.context.clock.time' isa Cropbox.Quantity{Rational{Int64}}
        @test s.context.clock.time' == 0u"d"
        @test s.context.clock.tick' === 0
        update!(s)
        @test s.context.clock.time' == 1u"d"
        @test s.context.clock.tick' === 1
        @test s.a' == 1
    end
end
