using DataFrames: DataFrame
using Dates
using TimeZones

@testset "provide" begin
    @testset "basic" begin
        @system SProvide(Controller) begin
            a => DataFrame(index=(0:3)u"hr", value=0:10:30) ~ provide
        end
        s = instance(SProvide)
        @test s.a'.index == [0, 1, 2, 3]u"hr"
        @test s.a'.value == [0, 10, 20, 30]
    end

    @testset "index" begin
        @system SProvideIndex(Controller) begin
            a => DataFrame(i=(0:3)u"hr", value=0:10:30) ~ provide(index=:i)
        end
        s = instance(SProvideIndex)
        @test s.a'.i == [0, 1, 2, 3]u"hr"
    end

    @testset "autounit" begin
        @system SProvideAutoUnit(Controller) begin
            a => DataFrame("index (hr)" => 0:3, "value (m)" => 0:10:30) ~ provide
            b => DataFrame("index" => (0:3)u"hr", "value (m)" => 0:10:30) ~ provide(autounit=false)
        end
        s = instance(SProvideAutoUnit)
        @test s.a'."index" == [0, 1, 2, 3]u"hr"
        @test s.a'."value" == [0, 10, 20, 30]u"m"
        @test s.b'."index" == [0, 1, 2, 3]u"hr"
        @test s.b'."value (m)" == [0, 10, 20, 30]
    end

    @testset "time" begin
        @system SProvideTime(Controller) begin
            a => DataFrame("index (d)" => 0:3, "value (m)" => 0:10:30) ~ provide
        end
        c = :Clock => :step => 1u"d"
        s = instance(SProvideTime; config=c)
        @test s.a'.index == [0, 1, 2, 3]u"d"
        @test s.a'.value == [0, 10, 20, 30]u"m"
        @test_throws ErrorException instance(SProvideTime)
    end

    @testset "tick" begin
        @system SProvideTick(Controller) begin
            a => DataFrame(index=0:3, value=0:10:30) ~ provide(init=context.clock.tick, step=1)
        end
        s = instance(SProvideTick)
        @test s.a'.index == [0, 1, 2, 3]
    end

    @testset "calendar" begin
        @system SProvideCalendar(Controller) begin
            calendar(context) ~ ::Calendar
            a ~ provide(init=calendar.time, step=calendar.step, parameter)
        end
        t0 = ZonedDateTime(2011, 10, 29, 0, tz"Asia/Seoul")
        t1 = ZonedDateTime(2011, 10, 29, 1, tz"Asia/Seoul")
        t2 = ZonedDateTime(2011, 10, 29, 3, tz"Asia/Seoul")
        Δt = Hour(1)
        df = DataFrame(index=t0:Δt:t2, value=0:3)
        c = (:Calendar => :init => t1, :0 => :a => df)
        s = instance(SProvideCalendar; config=c)
        @test s.a'.index == t1:Δt:t2
        @test s.a'.value == 1:3
    end

    @testset "parameter" begin
        @system SProvideParameter(Controller) begin
            a ~ provide(parameter)
        end
        df = DataFrame("index (hr)" => 0:3, "value (m)" => 0:10:30)
        c = :0 => :a => df
        s = instance(SProvideParameter; config=c)
        @test s.a'.index == [0, 1, 2, 3]u"hr"
        @test s.a'.value == [0, 10, 20, 30]u"m"
    end

    @testset "csv" begin
        @system SProvideCSV(Controller) begin
            a ~ provide(parameter)
        end
        s = mktemp() do f, io
            write(io, "index (hr),value\n0,0\n1,10\n2,20\n3,30")
            close(io)
            c = :0 => :a => f
            instance(SProvideCSV; config=c)
        end
        @test s.a'.index == [0, 1, 2, 3]u"hr"
        @test s.a'.value == [0, 10, 20, 30]
    end
end
