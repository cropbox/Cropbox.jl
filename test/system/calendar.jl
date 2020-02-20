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
end
