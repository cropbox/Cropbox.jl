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
        @test s.time' == ZonedDateTime(2011, 10, 29, 1, tz"Asia/Seoul")
        update!(s)
        @test s.time' == ZonedDateTime(2011, 10, 29, 2, tz"Asia/Seoul")
    end
end
