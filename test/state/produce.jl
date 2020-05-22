@testset "produce" begin
    @testset "basic" begin
        @system SProduce begin
            a => produce(SProduce) ~ produce
        end
        @system SProduceController(Controller) begin
            s(context) ~ ::SProduce
        end
        sc = instance(SProduceController)
        s = sc.s
        @test length(s.a) == 0
        update!(sc)
        @test length(s.a) == 1
        @test length(s.a[1].a) == 0
        update!(sc)
        @test length(s.a) == 2
        @test length(s.a[1].a) == 1
        @test length(s.a[2].a) == 0
    end

    @testset "single" begin
        @system SProduceSingle begin
            a => produce(SProduceSingle) ~ produce::SProduceSingle
        end
        @system SProduceSingleController(Controller) begin
            s(context) ~ ::SProduceSingle
        end
        sc = instance(SProduceSingleController)
        s = sc.s
        @test length(s.a) == 0
        update!(sc)
        @test length(s.a) == 1
        a = s.a[1]
        @test length(s.a[1].a) == 0
        update!(sc)
        @test length(s.a) == 1
        @test a === s.a[1]
        @test length(s.a[1].a) == 1
        @test_throws BoundsError s.a[2]
    end

    @testset "kwargs" begin
        @system SProduceKwargs begin
            a => produce(SProduceKwargs) ~ produce
            i(t=context.clock.tick) => t ~ preserve(u"hr")
        end
        @system SProduceKwargsController(Controller) begin
            s(context) ~ ::SProduceKwargs
        end
        sc = instance(SProduceKwargsController)
        s = sc.s
        @test length(s.a) == 0 && s.i' == 0u"hr"
        update!(sc)
        @test length(s.a) == 1 && s.i' == 0u"hr"
        @test length(s.a[1].a) == 0 && s.a[1].i' == 1u"hr"
        update!(sc)
        @test length(s.a) == 2 && s.i' == 0u"hr"
        @test length(s.a[1].a) == 1 && s.a[1].i' == 1u"hr"
        @test length(s.a[2].a) == 0 && s.a[2].i' == 2u"hr"
        @test length(s.a[1].a[1].a) == 0 && s.a[1].a[1].i' == 2u"hr"
    end

    @testset "nothing" begin
        @system SProduceNothing begin
            a => nothing ~ produce
        end
        @system SProduceNothingController(Controller) begin
            s(context) ~ ::SProduceNothing
        end
        sc = instance(SProduceNothingController)
        s = sc.s
        @test length(s.a) == 0
        update!(sc)
        @test length(s.a) == 0
    end

    @testset "query index" begin
        @system SProduceQueryIndex begin
            p => produce(SProduceQueryIndex) ~ produce::SProduceQueryIndex[]
            i(t=nounit(context.clock.tick)) => Int(t) ~ preserve::Int
            a(x=p["*"].i) => sum(x) ~ track
            b(x=p["**"].i) => sum(x) ~ track
            c(x=p["*/1"].i) => sum(x) ~ track
            d(x=p["*/-1"].i) => sum(x) ~ track
        end
        @system SProduceQueryIndexController(Controller) begin
            s(context) ~ ::SProduceQueryIndex
        end
        sc = instance(SProduceQueryIndexController)
        s = sc.s
        @test length(s.p) == 0
        update!(sc)
        @test length(s.p) == 1
        @test s.a' == 1 # (1)
        @test s.b' == 1 # (1)
        @test s.c' == 1 # (1*)
        @test s.d' == 1 # (1*)
        update!(sc)
        @test length(s.p) == 2
        @test s.a' == 3 # (1 + 2)
        @test s.b' == 5 # ((1 ~ 2) + 2)
        @test s.c' == 1 # (1* + 2)
        @test s.d' == 2 # (1 + 2*)
        update!(sc)
        @test length(s.p) == 3
        @test s.a' == 6 # (1 + 2 + 3)
        @test s.b' == 17 # ((1 ~ ((2 ~ 3) + 3) + (2 ~ 3) + 3)
        @test s.c' == 1 # (1* + 2 + 3)
        @test s.d' == 3 # (1 + 2 + 3*)
    end

    @testset "query condition with track bool" begin
        @system SProduceQueryConditionTrackBool begin
            p => produce(SProduceQueryConditionTrackBool) ~ produce::SProduceQueryConditionTrackBool[]
            i(t=nounit(context.clock.tick)) => Int(t) ~ preserve::Int
            f(i) => isodd(i) ~ track::Bool
            a(x=p["*/f"].i) => sum(x) ~ track
            b(x=p["**/f"].i) => sum(x) ~ track
            c(x=p["*/f/1"].i) => sum(x) ~ track
            d(x=p["*/f/-1"].i) => sum(x) ~ track
        end
        @system SProduceQueryConditionTrackBoolController(Controller) begin
            s(context) ~ ::SProduceQueryConditionTrackBool
        end
        sc = instance(SProduceQueryConditionTrackBoolController)
        s = sc.s
        @test length(s.p) == 0
        update!(sc)
        @test length(s.p) == 1
        @test s.a' == 1 # (#1)
        @test s.b' == 1 # (#1)
        @test s.c' == 1 # (#1*)
        @test s.d' == 1 # (#1*)
        update!(sc)
        @test length(s.p) == 2
        @test s.a' == 1 # (#1 + 2)
        @test s.b' == 1 # (#1 ~ 2) + 2)
        @test s.c' == 1 # (#1* + 2)
        @test s.d' == 1 # (#1* + 2)
        update!(sc)
        @test length(s.p) == 3
        @test s.a' == 4 # (#1 + 2 + #3)
        @test s.b' == 13 # ((#1 ~ ((2 ~ #3) + #3) + (2 ~ #3) + #3)
        @test s.c' == 1 # (1* + 2 + 3)
        @test s.d' == 3 # (1 + 2 + #3*)
        update!(sc)
        @test length(s.p) == 4
        @test s.a' == 4 # (#1 + 2 + #3 + 4)
        @test s.b' == 13 # ((#1 ~ (2 ~ (#3 ~ 4)) + (#3 ~ 4) + 4) + (2 ~ (#3 ~ 4)) + (#3 ~ 4) + 4)
        @test s.c' == 1 # (#1* + 2 + #3 + 4)
        @test s.d' == 3 # (#1 + 2 + #3* + 4)
    end

    @testset "query condition with flag" begin
        @system SProduceQueryConditionFlag begin
            p => produce(SProduceQueryConditionFlag) ~ produce::SProduceQueryConditionFlag[]
            i(t=nounit(context.clock.tick)) => Int(t) ~ preserve::Int
            f(i) => isodd(i) ~ flag
            a(x=p["*/f"].i) => sum(x) ~ track
            b(x=p["**/f"].i) => sum(x) ~ track
            c(x=p["*/f/1"].i) => sum(x) ~ track
            d(x=p["*/f/-1"].i) => sum(x) ~ track
        end
        @system SProduceQueryConditionFlagController(Controller) begin
            s(context) ~ ::SProduceQueryConditionFlag
        end
        sc = instance(SProduceQueryConditionFlagController)
        s = sc.s
        @test length(s.p) == 0
        update!(sc)
        @test length(s.p) == 1
        @test s.a' == 0 # (.1)
        @test s.b' == 0 # (.1)
        @test s.c' == 0 # (.1*)
        @test s.d' == 0 # (.1*)
        update!(sc)
        @test length(s.p) == 2
        @test s.a' == 1 # (#1 + .2)
        @test s.b' == 1 # (#1 ~ .2) + .2)
        @test s.c' == 1 # (#1* + .2)
        @test s.d' == 1 # (#1* + .2)
        update!(sc)
        @test length(s.p) == 3
        @test s.a' == 1 # (#1 + 2 + .3)
        @test s.b' == 1 # ((#1 ~ ((2 ~ .3) + .3) + (2 ~ .3) + .3)
        @test s.c' == 1 # (#1* + 2 + .3)
        @test s.d' == 1 # (#1* + 2 + .3)
        update!(sc)
        @test length(s.p) == 4
        @test s.a' == 4 # (#1 + 2 + #3 + .4)
        @test s.b' == 13 # ((#1 ~ (2 ~ (#3 ~ .4)) + (#3 ~ .4) + .4) + (2 ~ (#3 ~ .4)) + (#3 ~ .4) + .4)
        @test s.c' == 1 # (#1* + 2 + #3 + .4)
        @test s.d' == 3 # (#1 + 2 + #3* + .4)
    end

    @testset "adjoint" begin
        @system SProduceAdjoint begin
            p => produce(SProduceAdjoint) ~ produce::SProduceAdjoint[]
            i(t=nounit(context.clock.tick)) => Int(t) ~ preserve::Int
        end
        @system SProduceAdjointController(Controller) begin
            s(context) ~ ::SProduceAdjoint
        end
        sc = instance(SProduceAdjointController)
        s = sc.s
        update!(sc)
        @test length(s.p["*"]') == 1
        @test length(s.p["**"]') == 1
        @test s.p["*"].i' == [1]
        @test s.p["**"].i' == [1]
        update!(sc)
        @test length(s.p["*"]') == 2
        @test length(s.p["**"]') == 3
        @test s.p["*"].i' == [1, 2]
        @test s.p["**"].i' == [1, 2, 2]
    end
end
