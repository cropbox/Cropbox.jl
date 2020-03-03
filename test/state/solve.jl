@testset "solve" begin
    @testset "basic" begin
        @system SSolve(Controller) begin
            a ~ preserve(parameter)
            b ~ preserve(parameter)
            c ~ preserve(parameter)
            x(a, b, c) => begin
                a*x^2 + b*x + c
            end ~ solve
        end
        s1 = instance(SSolve, config=:SSolve => (a=1, b=2, c=1))
        @test s1.x' == -1
        s2 = instance(SSolve, config=:SSolve => (a=1, b=-2, c=1))
        @test s2.x' == 1
        s3 = instance(SSolve, config=:SSolve => (a=1, b=2, c=-3))
        @test s3.x' ∈ [1, -3]
        s4 = instance(SSolve, config=:SSolve => (a=1, b=-2, c=-3))
        @test s4.x' ∈ [-1, 3]
    end

    @testset "unit" begin
        @system SSolveUnit(Controller) begin
            a ~ preserve(u"m^-1", parameter)
            b ~ preserve(parameter)
            c ~ preserve(u"m", parameter)
            x(a, b, c) => begin
                a*x^2 + b*x + c
            end ~ solve(u"m")
        end
        s = instance(SSolveUnit, config=:SSolveUnit => (a=1, b=2, c=1))
        @test s.x' == -1u"m"
    end

    @testset "unit with scale" begin
        @system SSolveUnitScale(Controller) begin
            a ~ preserve(u"m^-1", parameter)
            b ~ preserve(u"cm/m", parameter) #HACK: caution with dimensionless unit!
            c ~ preserve(u"cm", parameter)
            x(a, b, c) => begin
                a*x^2 + b*x + c
            end ~ solve(u"cm")
        end
        s = instance(SSolveUnitScale, config=:SSolveUnitScale => (a=0.01, b=2, c=1))
        @test s.x' == -100u"cm"
    end

    @testset "linear" begin
        @system SSolveLinear(Controller) begin
            x => (2x ⩵ 1) ~ solve
        end
        s = instance(SSolveLinear)
        @test s.x' == 0.5
    end

    @testset "quadratic single" begin
        @system SSolveQuadraticSingle(Controller) begin
            x => (x^2 ⩵ 1) ~ solve
        end
        s = instance(SSolveQuadraticSingle)
        @test s.x' == 1
    end

    @testset "quadratic double" begin
        @system SSolveQuadraticDouble(Controller) begin
            l ~ preserve(parameter)
            u ~ preserve(parameter)
            x => (x^2 + 2x - 3) ~ solve(lower=l, upper=u)
        end
        s1 = instance(SSolveQuadraticDouble, config=:SSolveQuadraticDouble => (l=0, u=Inf))
        @test s1.x' == 1
        s2 = instance(SSolveQuadraticDouble, config=:SSolveQuadraticDouble => (l=-Inf, u=0))
        @test s2.x' == -3
    end

    @testset "cubic" begin
        @system SSolveCubic(Controller) begin
            l ~ preserve(parameter)
            u ~ preserve(parameter)
            x => ((x-5)*(x-15)*(x-25)) ~ solve(lower=l, upper=u)
        end
        s0 = instance(SSolveCubic, config=:SSolveCubic => (l=-Inf, u=0))
        @test s0.x' == 0
        s1 = instance(SSolveCubic, config=:SSolveCubic => (l=-Inf, u=10))
        @test s1.x' ≈ 5
        s2 = instance(SSolveCubic, config=:SSolveCubic => (l=10, u=20))
        @test s2.x' ≈ 15
        s3 = instance(SSolveCubic, config=:SSolveCubic => (l=20, u=30))
        @test s3.x' ≈ 25
        s4 = instance(SSolveCubic, config=:SSolveCubic => (l=30, u=Inf))
        @test s4.x' == 30
    end
end
