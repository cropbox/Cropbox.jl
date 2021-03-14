@testset "clock" begin
    @testset "basic" begin
        @system SClock(Controller)
        s = instance(SClock)
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

    @testset "daily" begin
        @system SClockDaily{Context => Cropbox.DailyContext}(Controller) begin
            a => 1 ~ accumulate
        end
        s = instance(SClockDaily)
        @test s.context isa Cropbox.DailyContext
        @test s.context.clock isa Cropbox.DailyClock
        @test s.context.clock.time' == 0u"d"
        @test s.context.clock.tick' === 0
        update!(s)
        @test s.context.clock.time' == 1u"d"
        @test s.context.clock.tick' === 1
        @test s.a' == 1
    end
end
