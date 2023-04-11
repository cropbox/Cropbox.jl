@testset "integrate" begin
    @testset "basic" begin
        @system SIntegrate(Controller) begin
            w => 1 ~ preserve(parameter)
            a => 0 ~ preserve(parameter)
            b => π ~ preserve(parameter)
            f(w; x) => w*sin(x) ~ integrate(from=a, to=b)
        end
        s1 = instance(SIntegrate)
        @test s1.f' ≈ 2
        s2 = instance(SIntegrate, config=:0 => :w => 2)
        @test s2.f' ≈ 4
        s3 = instance(SIntegrate, config=:0 => :a => π/2)
        @test s3.f' ≈ 1
        s4 = instance(SIntegrate, config=:0 => (a = π, b = 2π))
        @test s4.f' ≈ -2
    end

    @testset "unit" begin
        @system SIntegrateUnit(Controller) begin
            a => 1000 ~ preserve(u"mm")
            b => 3000 ~ preserve(u"mm")
            f1(; x) => x ~ integrate(from=a, to=b, u"cm^2")
            f2(; x(u"mm")) => x ~ integrate(from=a, to=b, u"cm^2")
            f3(; x(u"cm")) => x ~ integrate(from=a, to=b, u"cm^2")
            f4(; x(u"cm")) => x ~ integrate(from=a, to=b, u"m^2")
        end
        s = instance(SIntegrateUnit)
        @test s.f1' === 40000.0u"cm^2"
        @test s.f2' === 40000.0u"cm^2"
        @test s.f3' ≈ 4u"m^2"
        @test s.f3' isa typeof(40000.0u"cm^2")
        @test s.f4' ≈ 4u"m^2"
        @test s.f4' isa typeof(4.0u"m^2")
    end
end
