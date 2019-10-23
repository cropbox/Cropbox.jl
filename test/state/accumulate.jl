@testset "accumulate" begin
    @testset "basic" begin
        @system SAccumulate(Controller) begin
            a => 1 ~ track
            b(a) => a + 1 ~ accumulate
        end
        s = instance(SAccumulate)
        @test s.a' == 1 && s.b' == 0
        update!(s)
        @test s.a' == 1 && s.b' == 2
        update!(s)
        @test s.a' == 1 && s.b' == 4
        update!(s)
        @test s.a' == 1 && s.b' == 6
    end

    @testset "cross reference" begin
        @system SAccumulateXRef(Controller) begin
            a(b) => b + 1 ~ accumulate
            b(a) => a + 1 ~ accumulate
        end
        s = instance(SAccumulateXRef)
        @test s.a' == 0 && s.b' == 0
        update!(s)
        @test s.a' == 1 && s.b' == 1
        update!(s)
        @test s.a' == 3 && s.b' == 3
        update!(s)
        @test s.a' == 7 && s.b' == 7
    end

    @testset "cross reference mirror" begin
        @system SAccumulateXrefMirror1(Controller) begin
            a(b) => b + 1 ~ accumulate
            b(a) => a + 2 ~ accumulate
        end
        @system SAccumulateXrefMirror2(Controller) begin
            a(b) => b + 2 ~ accumulate
            b(a) => a + 1 ~ accumulate
        end
        s1 = instance(SAccumulateXrefMirror1); s2 = instance(SAccumulateXrefMirror2)
        @test s1.a' == s2.b' == 0 && s1.b' == s2.a' == 0
        update!(s1); update!(s2)
        @test s1.a' == s2.b' == 1 && s1.b' == s2.a' == 2
        update!(s1); update!(s2)
        @test s1.a' == s2.b' == 4 && s1.b' == s2.a' == 5
        update!(s1); update!(s2)
        @test s1.a' == s2.b' == 10 && s1.b' == s2.a' == 11
    end

    @testset "time" begin
        @system SAccumulateTime(Controller) begin
            t(x=context.clock.tick) => 0.5x ~ track(u"hr")
            a => 1 ~ track
            b(a) => a + 1 ~ accumulate
            c(a) => a + 1 ~ accumulate(time=t)
        end
        s = instance(SAccumulateTime)
        @test s.a' == 1 && s.b' == 0 && s.c' == 0
        update!(s)
        @test s.a' == 1 && s.b' == 2 && s.c' == 1
        update!(s)
        @test s.a' == 1 && s.b' == 4 && s.c' == 2
        update!(s)
        @test s.a' == 1 && s.b' == 6 && s.c' == 3
    end

    @testset "transport" begin
        @system SAccumulateTransport(Controller) begin
            a(a, b) => -max(a - b, 0) ~ accumulate(init=10)
            b(a, b, c) => max(a - b, 0) - max(b - c, 0) ~ accumulate
            c(b, c) => max(b - c, 0) ~ accumulate
        end
        s = instance(SAccumulateTransport)
        @test s.a' == 10 && s.b' == 0 && s.c' == 0
        update!(s)
        @test s.a' == 0 && s.b' == 10 && s.c' == 0
        update!(s)
        @test s.a' == 0 && s.b' == 0 && s.c' == 10
        update!(s)
        @test s.a' == 0 && s.b' == 0 && s.c' == 10
    end

    @testset "distribute" begin
        @system SAccumulateDistribute(Controller) begin
            s(x=context.clock.tick) => (100u"hr^-1" * x) ~ track
            d1(s) => 0.2s ~ accumulate
            d2(s) => 0.3s ~ accumulate
            d3(s) => 0.5s ~ accumulate
        end
        s = instance(SAccumulateDistribute)
        c = s.context
        @test c.clock.tick' == 1u"hr" && s.s' == 100 && s.d1' == 0 && s.d2' == 0 && s.d3' == 0
        update!(s)
        @test c.clock.tick' == 2u"hr" && s.s' == 200 && s.d1' == 20 && s.d2' == 30 && s.d3' == 50
        update!(s)
        @test c.clock.tick' == 3u"hr" && s.s' == 300 && s.d1' == 60 && s.d2' == 90 && s.d3' == 150
        update!(s)
        @test c.clock.tick' == 4u"hr" && s.s' == 400 && s.d1' == 120 && s.d2' == 180 && s.d3' == 300
    end
end
