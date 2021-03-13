using DataFrames: DataFrame

@testset "carry" begin
    @testset "basic" begin
        @system SCarry(Controller) begin
            a => [2, 4, 6] ~ carry
        end
        s = instance(SCarry)
        @test s.a' == 2
        update!(s)
        @test s.a' == 4
        update!(s)
        @test s.a' == 6
    end

    @testset "unit" begin
        @system SCarryUnit(Controller) begin
            a => [2, 4, 6] ~ carry(u"m")
        end
        s = instance(SCarryUnit)
        @test s.a' == 2u"m"
        update!(s)
        @test s.a' == 4u"m"
        update!(s)
        @test s.a' == 6u"m"
    end

    @testset "type" begin
        @system SCarryType(Controller) begin
            a => [2, 4, 6] ~ carry::Int(u"m")
        end
        s = instance(SCarryType)
        @test s.a' === 2u"m"
        update!(s)
        @test s.a' === 4u"m"
        update!(s)
        @test s.a' === 6u"m"
    end

    @testset "parameter" begin
        @system SCarryParameter(Controller) begin
            a ~ carry(parameter)
        end
        a = [2, 4, 6]
        c = :0 => :a => a
        s = instance(SCarryParameter; config=c)
        @test s.a' == 2
        update!(s)
        @test s.a' == 4
        update!(s)
        @test s.a' == 6
    end

    @testset "provide" begin
        @system SCarryProvide(Controller) begin
            p => DataFrame(index=(0:2)u"hr", a=[2,4,6], x=1:3, c=(4:6)u"m") ~ provide
            a ~ carry(from=p)
            b ~ carry(from=p, by=:x)
            c ~ carry(from=p, u"m")
        end
        s = instance(SCarryProvide)
        @test s.a' == 2
        @test s.b' == 1
        @test s.c' == 4u"m"
        update!(s)
        @test s.a' == 4
        @test s.b' == 2
        @test s.c' == 5u"m"
        update!(s)
        @test s.a' == 6
        @test s.b' == 3
        @test s.c' == 6u"m"
    end

    @testset "error" begin
        @test_throws LoadError @eval @system SCarryErrorMissingFrom(Controller) begin
            a ~ carry(by=:a)
        end

        @test_throws LoadError @eval @system SCarryErrorProvideParameter(Controller) begin
            p => DataFrame(index=(0:2)u"hr", a=[2,4,6]) ~ provide
            a ~ carry(from=p, parameter)
        end

        @test_throws LoadError @eval @system SCarryErrorProvideBody(Controller) begin
            p => DataFrame(index=(0:2)u"hr", a=[2,4,6]) ~ provide
            a => [1, 2, 3] ~ carry(from=p)
        end
    end
end
