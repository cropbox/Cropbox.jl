@testset "track" begin
    @testset "basic" begin
        @system STrack(Controller) begin
            a => 1 ~ track
            b => 2 ~ track
            c(a, b) => a + b ~ track
        end
        s = instance(STrack)
        @test s.a' == 1 && s.b' == 2 && s.c' == 3
    end

    @testset "cross reference" begin
        @test_throws LoadError @eval @system STrackXRef(Controller) begin
            a(b) => b ~ track
            b(a) => a ~ track
        end
    end

    @testset "self reference without init" begin
        @eval @system STrackSRefWithoutInit(Controller) begin
            a(a) => 2a ~ track
        end
        @test_throws UndefVarError instance(STrackSRefWithoutInit)
    end

    @testset "self reference with init" begin
        @system STrackSRefWithInit(Controller) begin
            a(a) => 2a ~ track(init=1)
        end
        r = simulate(STrackSRefWithInit, stop=3)
        @test r[!, :a] == [2, 4, 8, 16]
    end

    @testset "init" begin
        @system STrackInit(Controller) begin
            a(a) => a + 1 ~ track(init=0)
            b(b) => b + 1 ~ track(init=1)
            c(c) => c + 1 ~ track(init=i)
            d => 1 ~ track(init=i)
            i(t=context.clock.tick) => t + 1 ~ track
        end
        r = simulate(STrackInit, stop=3)
        @test r[!, :a] == [1, 2, 3, 4]
        @test r[!, :b] == [2, 3, 4, 5]
        @test r[!, :c] == [2, 3, 4, 5]
        @test r[!, :d] == [1, 1, 1, 1]
    end

    @testset "minmax" begin
        @system STrackMinMax(Controller) begin
            a => 0 ~ track(min=1)
            b => 0 ~ track(max=2)
            c => 0 ~ track(min=1, max=2)
        end
        s = instance(STrackMinMax)
        @test s.a' == 1
        @test s.b' == 0
        @test s.c' == 1
    end

    @testset "minmax unit" begin
        @system STrackMinMaxUnit(Controller) begin
            a => 0 ~ track(u"m", min=1)
            b => 0 ~ track(u"m", max=2u"cm")
            c => 0 ~ track(u"m", min=1u"cm", max=2)
        end
        s = instance(STrackMinMaxUnit)
        @test s.a' == 1u"m"
        @test s.b' == 0u"m"
        @test s.c' == 1u"cm"
    end

    @testset "round" begin
        @system STrackRound(Controller) begin
            a => 1.5 ~ track(round)
            b => 1.5 ~ track(round=:round)
            c => 1.5 ~ track(round=:ceil)
            d => -1.5 ~ track(round=:floor)
            e => -1.5 ~ track(round=:trunc)
        end
        s = instance(STrackRound)
        @test s.a' === s.b'
        @test s.b' === 2.0
        @test s.c' === 2.0
        @test s.d' === -2.0
        @test s.e' === -1.0
    end

    @testset "round int" begin
        @system STrackRoundInt(Controller) begin
            a => 1.5 ~ track::int(round)
            b => 1.5 ~ track::int(round=:round)
            c => 1.5 ~ track::int(round=:ceil)
            d => -1.5 ~ track::int(round=:floor)
            e => -1.5 ~ track::int(round=:trunc)
        end
        s = instance(STrackRoundInt)
        @test s.a' === s.b'
        @test s.b' === 2
        @test s.c' === 2
        @test s.d' === -2
        @test s.e' === -1
    end

    @testset "round int unit" begin
        @system STrackRoundIntUnit(Controller) begin
            a => 1.5 ~ track::int(u"d", round)
            b => 1.5 ~ track::int(u"d", round=:round)
            c => 1.5 ~ track::int(u"d", round=:ceil)
            d => -1.5 ~ track::int(u"d", round=:floor)
            e => -1.5 ~ track::int(u"d", round=:trunc)
        end
        s = instance(STrackRoundIntUnit)
        @test s.a' === s.b'
        @test s.b' === 2u"d"
        @test s.c' === 2u"d"
        @test s.d' === -2u"d"
        @test s.e' === -1u"d"
    end

    @testset "when" begin
        @system STrackWhen(Controller) begin
            T => true ~ preserve::Bool
            F => false ~ preserve::Bool
            a => 1 ~ track
            b => 1 ~ track(when=true)
            c => 1 ~ track(when=false)
            d => 1 ~ track(when=T)
            e => 1 ~ track(when=F)
            f => 1 ~ track(when=!F)
        end
        s = instance(STrackWhen)
        @test s.a' == 1
        @test s.b' == 1
        @test s.c' == 0
        @test s.d' == 1
        @test s.e' == 0
        @test s.f' == 1
    end

    @testset "when unit" begin
        @system STrackWhenUnit(Controller) begin
            T => true ~ preserve::Bool
            F => false ~ preserve::Bool
            a => 1 ~ track(u"d")
            b => 1 ~ track(u"d", when=true)
            c => 1 ~ track(u"d", when=false)
            d => 1 ~ track(u"d", when=T)
            e => 1 ~ track(u"d", when=F)
            f => 1 ~ track(u"d", when=!F)
        end
        s = instance(STrackWhenUnit)
        @test s.a' == 1u"d"
        @test s.b' == 1u"d"
        @test s.c' == 0u"d"
        @test s.d' == 1u"d"
        @test s.e' == 0u"d"
        @test s.f' == 1u"d"
    end

    @testset "when init" begin
        @system STrackWhenInit(Controller) begin
            T => true ~ preserve::Bool
            F => false ~ preserve::Bool
            I => 1 ~ preserve
            a => 0 ~ track(init=1, when=true)
            b => 0 ~ track(init=1, when=false)
            c => 0 ~ track(init=I, when=T)
            d => 0 ~ track(init=I, when=F)
        end
        s = instance(STrackWhenInit)
        @test s.a' == 0
        @test s.b' == 1
        @test s.c' == 0
        @test s.d' == 1
    end
end
