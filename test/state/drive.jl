using DataFrames: DataFrame

@testset "drive" begin
    @testset "basic" begin
        @system SDrive(Controller) begin
            a => [2, 4, 6] ~ drive
        end
        s = instance(SDrive)
        @test s.a' == 2
        update!(s)
        @test s.a' == 4
        update!(s)
        @test s.a' == 6
    end

    @testset "unit" begin
        @system SDriveUnit(Controller) begin
            a => [2, 4, 6] ~ drive(u"m")
        end
        s = instance(SDriveUnit)
        @test s.a' == 2u"m"
        update!(s)
        @test s.a' == 4u"m"
        update!(s)
        @test s.a' == 6u"m"
    end

    @testset "type" begin
        @system SDriveType(Controller) begin
            a => [2, 4, 6] ~ drive::Int(u"m")
        end
        s = instance(SDriveType)
        @test s.a' === 2u"m"
        update!(s)
        @test s.a' === 4u"m"
        update!(s)
        @test s.a' === 6u"m"
    end

    @testset "parameter" begin
        @system SDriveParameter(Controller) begin
            a ~ drive(parameter)
        end
        a = [2, 4, 6]
        c = :0 => :a => a
        s = instance(SDriveParameter; config=c)
        @test s.a' == 2
        update!(s)
        @test s.a' == 4
        update!(s)
        @test s.a' == 6
    end

    @testset "provide" begin
        @system SDriveProvide(Controller) begin
            p => DataFrame(index=(0:2)u"hr", a=[2,4,6], x=1:3, c=(4:6)u"m") ~ provide
            a ~ drive(from=p)
            b ~ drive(from=p, by=:x)
            c ~ drive(from=p, u"m")
        end
        s = instance(SDriveProvide)
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
        @test_throws LoadError @eval @system SDriveErrorMissingFrom(Controller) begin
            a ~ drive(by=:a)
        end

        @test_throws LoadError @eval @system SDriveErrorProvideParameter(Controller) begin
            p => DataFrame(index=(0:2)u"hr", a=[2,4,6]) ~ provide
            a ~ drive(from=p, parameter)
        end

        @test_throws LoadError @eval @system SDriveErrorProvideBody(Controller) begin
            p => DataFrame(index=(0:2)u"hr", a=[2,4,6]) ~ provide
            a => [1, 2, 3] ~ drive(from=p)
        end
    end
end
