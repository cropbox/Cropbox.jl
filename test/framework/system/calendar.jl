using TimeZones
import Dates

@testset "calendar" begin
    @testset "basic" begin
        @system SCalendar(Calendar, Controller)
        d = Dates.Date(2011, 10, 29)
        t0 = ZonedDateTime(d, tz"Asia/Seoul")
        o = :Calendar => :init => t0
        s = instance(SCalendar; config=o)
        @test s.init' == t0
        @test s.time' == t0
        @test s.date' == d
        @test s.step' == Dates.Hour(1)
        update!(s)
        @test s.time' == t0 + Dates.Hour(1)
        update!(s)
        @test s.time' == t0 + Dates.Hour(2)
    end
    
    @testset "stop" begin
        @system SCalendarStop(Calendar, Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        t1 = t0 + Dates.Day(1)
        o = :Calendar => (init=t0, last=t1)
        s = instance(SCalendarStop; config=o)
        @test s.init' == t0
        @test s.last' == t1
        @test s.time' == t0
        @test s.step' == Dates.Hour(1)
        @test s.stop' == false
        for i in 1:24
            update!(s)
        end
        @test s.time' == t1
        @test s.stop' == true
    end
    
    @testset "count" begin
        @system SCalendarCount(Calendar, Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        t1 = t0 + Dates.Day(1)
        n = 24
        o = :Calendar => (init=t0, last=t1)
        s = instance(SCalendarCount; config=o)
        @test s.count' == n
        r1 = simulate(SCalendarCount; config=o, stop=n)
        r2 = simulate(SCalendarCount; config=o, stop=:stop)
        r3 = simulate(SCalendarCount; config=o, stop=:count)
        @test r1 == r2 == r3
    end
    
    @testset "count nothing" begin
        @system SCalendarCountNothing(Calendar, Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        o = :Calendar => (init=t0, last=nothing)
        s = instance(SCalendarCountNothing; config=o)
        @test s.count' === nothing
        @test s.stop' == false
    end
    
    @testset "count seconds" begin
        @system SCalendarCountSeconds(Calendar, Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        t1 = t0 + Dates.Hour(1)
        n = 60*60
        o = (
            :Calendar => (init=t0, last=t1),
            :Clock => (step=1u"s",),
        )
        s = instance(SCalendarCountSeconds; config=o)
        @test s.count' == n
    end
end
