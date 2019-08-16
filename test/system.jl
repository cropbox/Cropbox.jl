@testset "system" begin
    @testset "derive" begin
        @system S begin
            a => 1 ~ track
            b => 2 ~ track
            c(a, b) => a + b ~ track
        end
        s = instance(S)
        @test s.a == 1 && s.b == 2 && s.c == 3
    end

    @testset "derive with cross reference" begin
        @system S begin
            a(b) => b ~ track
            b(a) => a ~ track
        end
        @test_throws StackOverflowError instance(S)
    end

    @testset "accumulate" begin
        @system S begin
            a => 1 ~ track
            b(a) => a + 1 ~ accumulate
        end
        s = instance(S)
        @test s.a == 1 && s.b == 0
        advance!(s)
        @test s.a == 1 && s.b == 2
        advance!(s)
        @test s.a == 1 && s.b == 4
        advance!(s)
        @test s.a == 1 && s.b == 6
    end

    @testset "accumulate with cross reference" begin
        @system S begin
            a(b) => b + 1 ~ accumulate
            b(a) => a + 1 ~ accumulate
        end
        s = instance(S)
        @test s.a == 0 && s.b == 0
        advance!(s)
        @test s.a == 1 && s.b == 1
        advance!(s)
        @test s.a == 3 && s.b == 3
        advance!(s)
        @test s.a == 7 && s.b == 7
    end

    @testset "accumulate with cross reference mirror" begin
        @system S1 begin
            a(b) => b + 1 ~ accumulate
            b(a) => a + 2 ~ accumulate
        end
        @system S2 begin
            a(b) => b + 2 ~ accumulate
            b(a) => a + 1 ~ accumulate
        end
        s1 = instance(S1); s2 = instance(S2)
        @test s1.a == s2.b && s1.b == s2.a
        advance!(s1); advance!(s2)
        @test s1.a == s2.b && s1.b == s2.a
        advance!(s1); advance!(s2)
        @test s1.a == s2.b && s1.b == s2.a
        advance!(s1); advance!(s2)
        @test s1.a == s2.b && s1.b == s2.a
    end

    @testset "accumulate with time" begin
        @system S begin
            a => 1 ~ track
            b(a) => a + 1 ~ accumulate
            c(a) => a + 1 ~ accumulate(time="t")
            t(x="context.clock.time") => 0.5x ~ track
        end
        s = instance(S)
        @test s.a == 1 && s.b == 0 && s.c == 0
        advance!(s)
        @test s.a == 1 && s.b == 2 && s.c == 1
        advance!(s)
        @test s.a == 1 && s.b == 4 && s.c == 2
        advance!(s)
        @test s.a == 1 && s.b == 6 && s.c == 3
    end

    @testset "accumulate transport" begin
        @system S begin
            a(a, b) => -max(a - b, 0) ~ accumulate(init=10)
            b(a, b, c) => max(a - b, 0) - max(b - c, 0) ~ accumulate
            c(b, c) => max(b - c, 0) ~ accumulate
        end
        s = instance(S)
        @test s.a == 10 && s.b == 0 && s.c == 0
        advance!(s)
        @test s.a == 0 && s.b == 10 && s.c == 0
        advance!(s)
        @test s.a == 0 && s.b == 0 && s.c == 10
        advance!(s)
        @test s.a == 0 && s.b == 0 && s.c == 10
    end

    @testset "accumulate distribute" begin
        @system S begin
            s(x="context.clock.time") => 100x ~ track
            d1(s) => 0.2s ~ accumulate
            d2(s) => 0.3s ~ accumulate
            d3(s) => 0.5s ~ accumulate
        end
        s = instance(S)
        c = s.context
        @test c.clock.time == 1 && s.s == 100 && s.d1 == 0 && s.d2 == 0 && s.d3 == 0
        advance!(s)
        @test c.clock.time == 2 && s.s == 200 && s.d1 == 20 && s.d2 == 30 && s.d3 == 50
        advance!(s)
        @test c.clock.time == 3 && s.s == 300 && s.d1 == 60 && s.d2 == 90 && s.d3 == 150
        advance!(s)
        @test c.clock.time == 4 && s.s == 400 && s.d1 == 120 && s.d2 == 180 && s.d3 == 300
    end

    @testset "preserve" begin
        @system S begin
            a => 1 ~ track
            b(a) => a + 1 ~ accumulate
            c(b) => b ~ preserve
        end
        s = instance(S)
        @test s.a == 1 && s.b == 0 && s.c == 0
        advance!(s)
        @test s.a == 1 && s.b == 2 && s.c == 0
    end

    @testset "parameter" begin
        @system S begin
            a => 1 ~ pass
        end
        s = instance(S)
        @test s.a == 1
        advance!(s)
        @test s.a == 1
    end

    @testset "parameter with config" begin
        @system S begin
            a => 1 ~ pass
            b(a) => a ~ track
        end
        config = configure(S => (:a => 2, :b => (:a => 3)))
        s = instance(S, config)
        @test s.a == 2
        @test s.b == 3
        advance!(s)
        @test s.a == 2
        @test s.b == 3
    end

    @testset "parameter with config alias" begin
        @system S begin
            a: aa => 1 ~ pass
            bb: b => 1 ~ pass
        end
        config = configure(S => (:a => 2, :b => 2))
        s = instance(S, config)
        @test s.a == 2
        @test s.b == 2
    end

    @testset "flag" begin
        @system S begin
            a => true ~ flag
            b => false ~ flag
            c => true ~ flag(prob=0)
            d => false ~ flag(prob=1)
            zero => 0 ~ track
            one => 1 ~ track
            e => true ~ flag(prob="zero")
            f => false ~ flag(prob="one")
        end
        s = instance(S)
        @test s.a == true && s.b == false
        @test s.c == false && s.d == false
        @test s.e == false && s.f == false
    end

    @testset "produce" begin
        @system S begin
            a(self) => produce(typeof(self)) ~ produce
        end
        s = instance(S)
        @test length(s.a) == 0
        advance!(s)
        @test length(s.a) == 1
        @test length(s.a[1].a) == 0
        advance!(s)
        @test length(s.a) == 2
        @test length(s.a[1].a) == 1
        @test length(s.a[2].a) == 0
    end

    @testset "produce with kwargs" begin
        @system S begin
            a(self) => produce(typeof(self)) ~ produce
            i(t="context.clock.time") => t ~ preserve
        end
        s = instance(S)
        @test length(s.a) == 0 && s.i == 1
        advance!(s)
        @test length(s.a) == 1 && s.i == 1
        @test length(s.a[1].a) == 0 && s.a[1].i == 2
        advance!(s)
        @test length(s.a) == 2 && s.i == 1
        @test length(s.a[1].a) == 1 && s.a[1].i == 2
        @test length(s.a[2].a) == 0 && s.a[2].i == 3
        @test length(s.a[1].a[1].a) == 0 && s.a[1].a[1].i == 3
    end

    @testset "produce with nothing" begin
        @system S begin
            a => nothing ~ produce
        end
        s = instance(S)
        @test length(s.a) == 0
        advance!(s)
        @test length(s.a) == 0
    end
end
