@testset "capture" begin
    @testset "basic" begin
        @system SCapture(Controller) begin
            a => 1 ~ track
            b(a) => a + 1 ~ capture
            c(a) => a + 1 ~ accumulate
        end
        s = instance(SCapture)
        @test s.b' == 0 && s.c' == 0
        update!(s)
        @test s.b' == 2 && s.c' == 2
        update!(s)
        @test s.b' == 2 && s.c' == 4
    end

    @testset "time" begin
        @system SCaptureTime(Controller) begin
            t(x=context.clock.time) => 2x ~ track(u"hr")
            a => 1 ~ track
            b(a) => a + 1 ~ capture(time=t)
            c(a) => a + 1 ~ accumulate(time=t)
        end
        s = instance(SCaptureTime)
        @test s.b' == 0 && s.c' == 0
        update!(s)
        @test s.b' == 4 && s.c' == 4
        update!(s)
        @test s.b' == 4 && s.c' == 8
    end

    @testset "unit hour" begin
        @system SCaptureUnitHour(Controller) begin
            a => 1 ~ capture(u"hr")
        end
        s = instance(SCaptureUnitHour)
        @test iszero(s.a')
        update!(s)
        @test s.a' == 1u"hr"
        update!(s)
        @test s.a' == 1u"hr"
    end

    @testset "unit day" begin
        @system SCaptureUnitDay(Controller) begin
            a => 1 ~ capture(u"d")
        end
        s = instance(SCaptureUnitDay)
        @test iszero(s.a')
        update!(s)
        @test s.a' == 1u"hr"
        update!(s)
        @test s.a' == 1u"hr"
    end

    @testset "when" begin
        @system SCaptureWhen(Controller) begin
            t(context.clock.tick) ~ track::int
            f ~ preserve(parameter)
            w(t, f) => t <= f ~ flag
            a => 1 ~ capture
            b => 1 ~ capture(when=w)
            c => 1 ~ capture(when=!w)
        end
        n = 5
        s = instance(SCaptureWhen; config=:0 => :f => n)
        simulate!(s, stop=n)
        @test s.a' == 1
        @test s.b' == 1
        @test s.c' == 0
        simulate!(s, stop=n)
        @test s.a' == 1
        @test s.b' == 0
        @test s.c' == 1
    end
end
