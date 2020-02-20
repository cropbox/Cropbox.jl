using TimeZones
import Dates

@testset "calendar" begin
    @testset "basic" begin
        @system SCalendar(Calendar, Controller)
        t0 = ZonedDateTime(2011, 10, 29, tz"Asia/Seoul")
        o = :Calendar => :init => t0
        s = instance(SCalendar; config=o)
        # after one advance! in instance()
        @test s.init' == t0
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
        @test s.time' == t0 + Dates.Hour(1)
        @test s.stop' == false
        for i in 1:24
            update!(s)
        end
        @test s.time' == t1 + Dates.Hour(1)
        @test s.stop' == true
    end
end
