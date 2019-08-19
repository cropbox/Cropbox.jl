using Unitful

@testset "unit" begin
    @testset "unit" begin
        @system S begin
            a => 2 ~ track(u"m")
            b => 1 ~ track(u"s")
            c(a, b) => a / b ~ track(u"m/s")
        end
        s = instance(S)
        @test s.a == 2u"m" && s.b == 1u"s" && s.c == 2u"m/s"
    end

    @testset "nounit" begin
        @system S begin
            a => 1 ~ track(u"m")
            b(a) => a ~ track(nounit="a")
        end
        s = instance(S)
        @test s.a == u"1m"
        @test s.b == 1
    end

    @testset "nounit with alias" begin
        @system S begin
            a: aa => 1 ~ track(u"m")
            b(aa): bb => aa ~ track(nounit="aa")
        end
        s = instance(S)
        @test s.aa == u"1m"
        @test s.bb == 1
    end

    @testset "nounit with call" begin
        @system S begin
            a => 1 ~ track(u"m")
            b(a,x) => a+x ~ call(nounit="a")
            c(b) => b(1) ~ track
        end
        s = instance(S)
        @test s.a == u"1m"
        @test value(s.b)(1) == 2
        @test s.c == 2
    end
end
