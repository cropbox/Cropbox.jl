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
        @test propertynames(r) == [:tick, :a, :b]
        @test r[end, :tick] == n*u"hr"
        @test r[end, :a] == 1
        @test r[end, :b] == n
        r = simulate(SSimulate, stop=n, config=(:SSimulate => :a => 2))
        @test r[end, :a] == 2
        @test r[end, :b] == 2n
        r = simulate(SSimulate, stop=n, target=[:b])
        @test size(r, 2) == 2
        @test propertynames(r) == [:tick, :b]
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

    @testset "stop count" begin
        @system SSimulateStopCount(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
            c => 5 ~ preserve::Int
        end
        r = simulate(SSimulateStopCount, stop=:c)
        @test r[end-1, :b] == 4
        @test r[end, :b] == 5
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

    @testset "skipfirst" begin
        @system SSimulateSkipFirst(Controller) begin
            a => 1 ~ preserve
            b(a) ~ accumulate
        end
        r0 = simulate(SSimulateSkipFirst, stop=1, skipfirst=false)
        r1 = simulate(SSimulateSkipFirst, stop=1, skipfirst=true)
        @test nrow(r0) == 2
        @test nrow(r1) == 1
        @test r0[end, :] == r0[end, :]
    end

    @testset "filter" begin
        @system SSimulateFilter(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
            f(b) => (b % 2 == 0) ~ track::Bool
        end
        n = 10
        f(s) = s.b' % 2 == 0
        r0 = simulate(SSimulateFilter, stop=n, filter=nothing)
        @test !all(r0.b .% 2 .== 0)
        r1 = simulate(SSimulateFilter, stop=n, filter=f)
        @test all(r1.b .% 2 .== 0)
        r2 = simulate(SSimulateFilter, stop=n, filter=:f)
        @test all(r2.b .% 2 .== 0)
        r3 = simulate(SSimulateFilter, stop=n, filter="f")
        @test all(r3.b .% 2 .== 0)
    end

    @testset "callback" begin
        @system SSimulateCallback(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 3
        i = 0
        f(s, m) = begin
            r = m.result[end, :]
            @test s.a' == r.a && s.b' == r.b
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
            (index=[:t => "context.clock.tick", "i"], target=["a", :B => :b]),
            (base="context.clock", index="tick", target="step"),
            (target=:b, meta=(:c => 0, :d => :D)),
        ]
        n = 1
        r = simulate(SSimulateLayout, L, stop=n)
        @test propertynames(r[1]) == [:tick, :a]
        @test propertynames(r[2]) == [:t, :i, :a, :B]
        @test propertynames(r[3]) == [:tick, :step]
        @test propertynames(r[4]) == [:tick, :b, :c, :d]
        @test r[1][end, :tick] == r[2][end, :t] == r[3][end, :tick] == r[4][end, :tick] == n*u"hr"
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
            (index=:t => "context.clock.tick", target=:b),
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
        @test o[o.tick .== n*u"hr", :i] == [n, n]
        @test o[o.tick .== n*u"hr", :a] == [p1*(n-1), p2*(n-1)]
        @test o[o.tick .== n*u"hr", :b] == [2p1*n, 2p2*n]
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
        @test r[r.tick .== n*u"hr", :a] == p
        @test r[r.tick .== n*u"hr", :b] == p .* n
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

    @testset "options" begin
        @system SSimulateOptions(Controller) begin
            a ~ preserve(extern)
            b ~ ::Int(override)
        end
        n = 10
        a, b = 1, 2
        o = (; a=a, b=b)
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
        @test r1[end, :a] == 0.5392892841426182
        @test r1[end, :b] == 3.766035118243237
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
            b => :hello ~ track::Symbol
            c => "world" ~ track::String
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
