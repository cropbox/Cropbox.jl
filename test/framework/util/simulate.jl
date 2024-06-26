using DataFrames
using Dates

@testset "simulate" begin
    @testset "basic" begin
        @system SSimulate(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 10
        r = simulate(SSimulate, stop=n)
        @test r isa DataFrame
        @test size(r, 1) == (n+1)
        @test propertynames(r) == [:time, :a, :b]
        @test r[end, :time] == n*u"hr"
        @test r[end, :a] == 1
        @test r[end, :b] == n
        r = simulate(SSimulate, stop=n, config=(:SSimulate => :a => 2))
        @test r[end, :a] == 2
        @test r[end, :b] == 2n
        r = simulate(SSimulate, stop=n, target=[:b])
        @test size(r, 2) == 2
        @test propertynames(r) == [:time, :b]
        r = simulate(SSimulate, stop=n, index=:b, target=[:b])
        @test size(r, 2) == 1
        @test propertynames(r) == [:b]
    end

    @testset "stop number" begin
        @system SSimulateStopNumber(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        r = simulate(SSimulateStopNumber, stop=5)
        @test r[end-1, :b] == 4
        @test r[end, :b] == 5
    end

    @testset "stop number unit" begin
        @system SSimulateStopNumberUnit(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        r1 = simulate(SSimulateStopNumberUnit, stop=2u"hr")
        @test r1[end, :b] == 2 * 1
        r2 = simulate(SSimulateStopNumberUnit, stop=2u"d")
        @test r2[end, :b] == 2 * 24
        r3 = simulate(SSimulateStopNumberUnit, stop=2u"yr")
        @test r3[end, :b] == 2 * 24 * 365.25
    end

    @testset "stop count" begin
        @system SSimulateStopCount(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
            c => 5 ~ preserve::int
        end
        r = simulate(SSimulateStopCount, stop=:c)
        @test r[end-1, :b] == 4
        @test r[end, :b] == 5
    end

    @testset "stop count unit" begin
        @system SSimulateStopCountUnit(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
            c ~ preserve::Cropbox.Quantity(parameter)
        end
        r1 = simulate(SSimulateStopCountUnit, stop=:c, config=:0 => :c => 2u"hr")
        @test r1[end, :b] == 2 * 1
        r2 = simulate(SSimulateStopCountUnit, stop=:c, config=:0 => :c => 2u"d")
        @test r2[end, :b] == 2 * 24
        r3 = simulate(SSimulateStopCountUnit, stop=:c, config=:0 => :c => 2u"yr")
        @test r3[end, :b] == 2 * 24 * 365.25
    end

    @testset "stop boolean" begin
        @system SSimulateStopBoolean(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
            z(b) => b >= 5 ~ flag
        end
        r1 = simulate(SSimulateStopBoolean, stop=:z)
        @test r1[end-1, :b] == 4
        @test r1[end, :b] == 5
        r2 = simulate(SSimulateStopBoolean, stop="z")
        @test r1 == r2
        r3 = simulate(SSimulateStopBoolean, stop=s -> s.b' >= 5)
        @test r1 == r3
    end

    @testset "snap" begin
        @system SSimulateSnap(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
            f(b) => (b % 2 == 0) ~ flag
        end
        n = 10
        f(s) = s.b' % 2 == 0
        r0 = simulate(SSimulateSnap, stop=n, snap=nothing)
        @test !all(r0.b .% 2 .== 0)
        r1 = simulate(SSimulateSnap, stop=n, snap=f)
        @test all(r1.b .% 2 .== 0)
        r2 = simulate(SSimulateSnap, stop=n, snap=:f)
        @test all(r2.b .% 2 .== 0)
        r3 = simulate(SSimulateSnap, stop=n, snap="f")
        @test all(r3.b .% 2 .== 0)
    end

    @testset "snatch" begin
        @system SSimulateSnatch(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 3
        i = 0
        f(D, s) = begin
            d = D[1]
            @test s.a' == d[:a] && s.b' == d[:b]
            i += 1
            d[:c] = i
        end
        r = simulate(SSimulateSnatch, stop=n, snatch=f)
        @test i == 1 + n
        @test r[!, :c] == [1, 2, 3, 4]
    end

    @testset "callback" begin
        @system SSimulateCallback(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 3
        i = 0
        f(s, m) = begin
            r = m.result[end]
            @test s.a' == r[:a] && s.b' == r[:b]
            i += 1
        end
        simulate(SSimulateCallback, stop=n, callback=f)
        @test i == n
    end

    @testset "layout" begin
        @system SSimulateLayout(Controller) begin
            i => 1 ~ accumulate
            a(i) => i-1 ~ track
            b(i) => 2i ~ track
        end
        L = [
            (target=:a,),
            (index=[:t => "context.clock.time", "i"], target=["a", :B => :b]),
            (base="context.clock", index="time", target="step"),
            (target=:b, meta=(:c => 0, :d => :D)),
        ]
        n = 1
        r = simulate(SSimulateLayout, L, stop=n)
        @test propertynames(r[1]) == [:time, :a]
        @test propertynames(r[2]) == [:t, :i, :a, :B]
        @test propertynames(r[3]) == [:time, :step]
        @test propertynames(r[4]) == [:time, :b, :c, :d]
        @test r[1][end, :time] == r[2][end, :t] == r[3][end, :time] == r[4][end, :time] == n*u"hr"
        @test r[1][end, :a] == 0
        @test r[2][end, :B] == 2
        @test r[3][end, :step] == 1u"hr"
        @test all(r[4][!, :c] .== 0) && all(r[4][!, :d] .== :D)
    end

    @testset "layout and configs" begin
        @system SSimulateLayoutConfigs(Controller) begin
            p ~ preserve(parameter)
            i => 1 ~ accumulate
            a(i, p) => p*(i-1) ~ track
            b(i, p) => 2p*i ~ track
        end
        L = [
            (index=:i, target=:a),
            (index=:t => "context.clock.time", target=:b),
            (target=[:i, :a, :b],),
        ]
        p1, p2 = 1, 2
        C = [
            :SSimulateLayoutConfigs => :p => p1,
            :SSimulateLayoutConfigs => :p => p2,
        ]
        n = 10
        r = simulate(SSimulateLayoutConfigs, L, C, stop=n)
        @test length(r) == length(L)
        o = r[3]
        @test o[o.time .== n*u"hr", :i] == [n, n]
        @test o[o.time .== n*u"hr", :a] == [p1*(n-1), p2*(n-1)]
        @test o[o.time .== n*u"hr", :b] == [2p1*n, 2p2*n]
    end

    @testset "configs" begin
        @system SSimulateConfigs(Controller) begin
            a ~ preserve(parameter)
            b(a) ~ accumulate
        end
        p = [1, 2]
        C = @config !(:SSimulateConfigs => :a => p)
        n = 10
        r = simulate(SSimulateConfigs, configs=C, stop=n)
        @test r[r.time .== n*u"hr", :a] == p
        @test r[r.time .== n*u"hr", :b] == p .* n
    end

    @testset "config and configs" begin
        @system SSimulateConfigConfigs(Controller) begin
            x ~ preserve(parameter)
            a ~ preserve(parameter)
            b(a) ~ accumulate
        end
        x = 0
        A = [1, 2]
        c = @config :SSimulateConfigConfigs => :x => x
        C = @config !(:SSimulateConfigConfigs => :a => A)
        n = 10
        r = simulate(SSimulateConfigConfigs; config=c, configs=C, stop=n)
        @test all(r[r.time .== n*u"hr", :x] .== x)
        @test r[r.time .== n*u"hr", :a] == A
        @test r[r.time .== n*u"hr", :b] == A .* n
    end

    @testset "meta" begin
        @system SSimulateMeta(Controller) begin
            a ~ preserve(parameter)
            b(a) ~ accumulate
        end
        C = (
            :SSimulateMeta => (a=1,),
            :Extra => (b=2, c=:C),
        )
        n = 10
        r1 = simulate(SSimulateMeta, config=C, index=(), meta=:Extra, stop=n)
        @test propertynames(r1) == [:a, :b, :c]
        @test all(r1.b .== 2)
        @test all(r1.c .== :C)
        r2 = simulate(SSimulateMeta, config=C, index=(), meta=(:Extra, :d => 0), stop=n)
        @test propertynames(r2) == [:a, :b, :c, :d]
        @test r1.b == r2.b
        @test r1.c == r2.c
        @test all(r2.d .== 0)
    end

    @testset "wildcard" begin
        @system SSimulateWildcardA begin
            x => 1 ~ preserve
            y => 2 ~ preserve
        end
        @system SSimulateWildcard(Controller) begin
            A(context) ~ ::SSimulateWildcardA
            a => 3 ~ preserve
            b => 4 ~ preserve
        end
        r1 = simulate(SSimulateWildcard; target="*")
        @test names(r1) == ["time", "a", "b"]
        @test collect(r1[1,:]) == [0u"hr", 3, 4]
        r2 = simulate(SSimulateWildcard; target="A.*")
        @test names(r2) == ["time", "A.x", "A.y"]
        @test collect(r2[1,:]) == [0u"hr", 1, 2]
        r3 = simulate(SSimulateWildcard; target=["*", "A.*"])
        @test names(r3) == ["time", "a", "b", "A.x", "A.y"]
        @test collect(r3[1,:]) == [0u"hr", 3, 4, 1, 2]
        r4 = simulate(SSimulateWildcard; target=["A.*", "*"])
        @test names(r4) == ["time", "A.x", "A.y", "a", "b"]
        @test collect(r4[1,:]) == [0u"hr", 1, 2, 3, 4]
    end

    @testset "options" begin
        @system SSimulateOptions(Controller) begin
            a ~ preserve(extern)
            b ~ ::int(override)
        end
        n = 10
        a, b = 1, 2
        o = (; a, b)
        r = simulate(SSimulateOptions, options=o, stop=n)
        @test r[end, :a] == a
        @test r[end, :b] == b
    end

    @testset "seed" begin
        @system SSimulateSeed(Controller) begin
            a => rand() ~ track
            b(a) ~ accumulate
        end
        n = 10
        r1 = simulate(SSimulateSeed, seed=0, stop=n)
        if VERSION >= v"1.7"
            @test r1[end, :a] == 0.8969897902567084
            @test r1[end, :b] == 3.462686872284925
        else
            @test r1[end, :a] == 0.5392892841426182
            @test r1[end, :b] == 3.766035118243237
        end
        r2 = simulate(SSimulateSeed, seed=0, stop=n)
        @test r1 == r2
    end

    @testset "no seed" begin
        @system SSimulateNoSeed(Controller) begin
            a => rand() ~ track
            b(a) ~ accumulate
        end
        n = 10
        r1 = simulate(SSimulateNoSeed, seed=nothing, stop=n)
        r2 = simulate(SSimulateNoSeed, seed=nothing, stop=n)
        @test r1 != r2
    end

    @testset "extractable" begin
        @system SSimulateExtractable(Controller) begin
            a => 1 ~ track
            b => :hello ~ track::sym
            c => "world" ~ track::str
            d => DateTime(2020, 3, 1) ~ track::DateTime
            e => Dict(:k => 0) ~ track::Dict
            f => [1, 2, 3] ~ track::Vector
            g => (1, 2) ~ track::Tuple
        end
        r = simulate(SSimulateExtractable)
        N = propertynames(r)
        # default = Union{Number,Symbol,AbstractString,AbstractDateTime}
        @test :a ∈ N
        @test :b ∈ N
        @test :c ∈ N
        @test :d ∈ N
        @test :e ∉ N
        @test :f ∉ N
        @test :g ∉ N
    end
end
