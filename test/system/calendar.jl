using TimeZones
import Dates

@testset "calendar" begin
    @testset "basic" begin
        @system SCalendar(Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        o = :Calendar => :init => t0
        s = instance(SCalendar; config=o)
        c = s.context.calendar
        # after one advance! in instance()
        @test c.init' == t0
        @test c.time' == t0 + Dates.Hour(1)
        update!(s)
        @test c.time' == t0 + Dates.Hour(2)
    end
    
    @testset "stop" begin
        @system SCalendarStop(Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        t1 = t0 + Dates.Day(1)
        o = :Calendar => (init=t0, last=t1)
        s = instance(SCalendarStop; config=o)
        c = s.context.calendar
        @test c.init' == t0
        @test c.last' == t1
        @test c.time' == t0 + Dates.Hour(1)
        @test c.stop' == false
        for i in 1:24
            update!(s)
        end
        @test c.time' == t1 + Dates.Hour(1)
        @test c.stop' == true
    end
    
    @testset "count" begin
        @system SCalendarCount(Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        t1 = t0 + Dates.Day(1)
        n = 24 - 1
        o = :Calendar => (init=t0, last=t1)
        s = instance(SCalendarCount; config=o)
        c = s.context.calendar
        @test c.count' == n
        r1 = simulate(SCalendarCount; config=o, stop=n)
        r2 = simulate(SCalendarCount; config=o, stop="context.calendar.stop")
        r3 = simulate(SCalendarCount; config=o, stop="context.calendar.count")
        @test r1 == r2 == r3
    end
    
    @testset "count nothing" begin
        @system SCalendarCountNothing(Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        o = :Calendar => (init=t0, last=nothing)
        s = instance(SCalendarCountNothing; config=o)
        c = s.context.calendar
        @test c.count' == nothing
        @test c.stop' == false
    end
    
    @testset "count seconds" begin
        @system SCalendarCountSeconds(Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        t1 = t0 + Dates.Hour(1)
        n = 60*60 - 1
        o = (
            :Calendar => (init=t0, last=t1),
            :Clock => (step=1u"s",),
        )
        s = instance(SCalendarCountSeconds; config=o)
        c = s.context.calendar
        @test c.count' == n
    end
end
