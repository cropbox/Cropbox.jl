@testset "advance" begin
    @testset "basic" begin
        @system SAdvance(Controller) begin
            a ~ advance
        end
        s = instance(SAdvance)
        @test s.a' == 0
        update!(s)
        @test s.a' == 1
        update!(s)
        @test s.a' == 2
    end

    @testset "custom" begin
        @system SAdvanceCustom(Controller) begin
            i => 1 ~ preserve(parameter)
            s => 2 ~ preserve(parameter)
            a ~ advance(init=i, step=s)
        end
        s1 = instance(SAdvanceCustom)
        @test s1.a' == 1
        update!(s1)
        @test s1.a' == 3
        update!(s1)
        @test s1.a' == 5
        c = :0 => (i = 10, s = 20)
        s2 = instance(SAdvanceCustom, config=c)
        s2.a' == 10
        update!(s2)
        s2.a' == 30
        update!(s2)
        s2.a' == 50
    end

    @testset "unit" begin
        @system SAdvanceUnit(Controller) begin
            a ~ advance(init=1, step=2, u"d")
        end
        s = instance(SAdvanceUnit)
        @test s.a' == 1u"d"
        update!(s)
        @test s.a' == 3u"d"
        update!(s)
        @test s.a' == 5u"d"
    end

    @testset "type" begin
        @system SAdvanceType(Controller) begin
            a ~ advance::int
        end
        s = instance(SAdvanceType)
        @test s.a' === 0
        update!(s)
        @test s.a' === 1
        update!(s)
        @test s.a' === 2
    end
end
