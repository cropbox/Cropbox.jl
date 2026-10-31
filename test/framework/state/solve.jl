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

    @testset "equal" begin
        @system SSolveEqual(Controller) begin
            x1 => (x1^2 + 2x1 - 3) ~ solve
            x2 => (x2^2 + 2x2 - 3 ⩵ 0) ~ solve
        end
        s = instance(SSolveEqual)
        @test s.x1' == s.x2'
    end

    @testset "missing coefficients" begin
        @system SSolveSparse(Controller) begin
            x => 2x ~ solve
            y => (y^2 ⩵ 4) ~ solve
            z => (z^2 ⩵ 4) ~ solve(pick=:minimum)
            w => (w^2 - 2w) ~ solve(pick=:minimum)
            r => (r^3 ⩵ 8) ~ solve
        end
        s = instance(SSolveSparse)
        @test s.x' == 0
        @test s.y' == 2
        @test s.z' == -2
        @test s.w' == 0
        @test s.r' ≈ 2

        @system SSolveSparseUnit(Controller) begin
            a => 1 ~ preserve(u"m^-1")
            c => -4 ~ preserve(u"m")
            x(a, c) => (a*x^2 + c) ~ solve(u"cm")
        end
        @test instance(SSolveSparseUnit).x' == 200u"cm"
    end

    @testset "symbolic coefficients" begin
        @system SSolveCoefficients(Controller) begin
            a => π/2 ~ preserve
            x(a) => (x + sin(a)) ~ solve
        end
        @test instance(SSolveCoefficients).x' ≈ -1
        x = only(Cropbox.Symbolics.@variables x)
        for p in (x + sin(x), x + 1/x)
            @test_throws ArgumentError Cropbox.genpolynomialcoeffs(p, x)
        end
        @test Cropbox.genpolynomialexpr(Cropbox.Symbolics.Num(1//10^12)) === 1e-12
    end

    @testset "vanishing leading coefficients" begin
        @test instance(SSolve, config=:SSolve => (a=0, b=2, c=-4)).x' == 2
        @test instance(SSolveUnitScale, config=:SSolveUnitScale => (a=0, b=2, c=1)).x' == -50u"cm"

        @system SSolveVaryingDegree(Controller) begin
            a ~ preserve(parameter)
            b ~ preserve(parameter)
            c ~ preserve(parameter)
            d ~ preserve(parameter)
            x(a, b, c, d) => (a*x^3 + b*x^2 + c*x + d) ~ solve(pick=:minimum, lower=-3, upper=3)
        end
        @test instance(SSolveVaryingDegree, config=:SSolveVaryingDegree => (a=0, b=1, c=0, d=-4)).x' == -2
        @test instance(SSolveVaryingDegree, config=:SSolveVaryingDegree => (a=0, b=0, c=2, d=-4)).x' == 2
        @test instance(SSolveVaryingDegree, config=:SSolveVaryingDegree => (a=0, b=0, c=1, d=-4)).x' == 3
        for d in (0, 1)
            @test_throws ArgumentError instance(SSolveVaryingDegree, config=:SSolveVaryingDegree => (a=0, b=0, c=0, d=d))
        end

        @system SSolveBallBerry(Controller) begin
            g0 => 0.01 ~ preserve(u"mol/m^2/s/bar", parameter)
            g1 => 13.1 ~ preserve(parameter)
            gb => 0.5 ~ preserve(u"mol/m^2/s/bar")
            A_net => 20 ~ preserve(u"μmol/m^2/s", parameter)
            Cs => 400 ~ preserve(u"μbar")
            RH => 60 ~ preserve(u"percent")
            hs(g0, g1, gb, A_net, Cs, RH) => begin
                gs = g0 + g1*A_net*hs/Cs
                (hs-RH)*gb ⩵ (1-hs)*gs
            end ~ solve(lower=0, upper=1)
        end
        for config in ((A_net=0,), (g1=0,))
            s = instance(SSolveBallBerry; config=:SSolveBallBerry => config)
            @test s.hs' ≈ (0.5*0.6+0.01)/(0.5+0.01)
        end
        @test instance(SSolveBallBerry, config=:SSolveBallBerry => (g0=0, A_net=0)).hs' ≈ 0.6
    end
end
