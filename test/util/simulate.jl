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
        @test names(r) == [:tick, :a, :b]
        @test r[end, :tick] == (n+1)u"hr"
        @test r[end, :a] == 1
        @test r[end, :b] == n
        r = simulate(SSimulate, stop=n, config=(:SSimulate => :a => 2))
        @test r[end, :a] == 2
        @test r[end, :b] == 2n
        r = simulate(SSimulate, stop=n, target=[:b])
        @test size(r, 2) == 2
        @test names(r) == [:tick, :b]
        r = simulate(SSimulate, stop=n, index=:b, target=[:b])
        @test size(r, 2) == 1
        @test names(r) == [:b]
    end

    @testset "stop" begin
        @system SSimulateStop(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
            z(b) => b >= 10 ~ flag
        end
        r = simulate(SSimulateStop, stop="z")
        @test r[end, :b] == 10
        @test r[end-1, :b] != 10
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

    @testset "callback" begin
        @system SSimulateCallback(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 10
        cb(s) = s.b' % 2 == 0
        r0 = simulate(SSimulateCallback, stop=n, callback=nothing)
        @test !all(r0[!, :b] .% 2 .== 0)
        r1 = simulate(SSimulateCallback, stop=n, callback=cb)
        @test all(r1[!, :b] .% 2 .== 0)
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
        ]
        n = 1
        r = simulate(SSimulateLayout, L, stop=n)
        @test names(r[1]) == [:tick, :a]
        @test names(r[2]) == [:t, :i, :a, :B]
        @test names(r[3]) == [:tick, :step]
        @test r[1][end, :tick] == r[2][end, :t] == r[3][end, :tick] == (n+1)u"hr"
        @test r[1][end, :a] == 0
        @test r[2][end, :B] == 2
        @test r[3][end, :step] == 1u"hr"
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
        @test o[o[!, :tick] .== (n+1)*u"hr", :i] == [n, n]
        @test o[o[!, :tick] .== (n+1)*u"hr", :a] == [p1*(n-1), p2*(n-1)]
        @test o[o[!, :tick] .== (n+1)*u"hr", :b] == [2p1*n, 2p2*n]
    end

    @testset "configs" begin
        @system SSimulateConfigs(Controller) begin
            a ~ preserve(parameter)
            b(a) ~ accumulate
        end
        p = [1, 2]
        C = Cropbox.configexpand(:SSimulateConfigs => :a => p)
        n = 10
        r = simulate(SSimulateConfigs, configs=C, stop=n)
        @test r[r[!, :tick] .== (n+1)*u"hr", :a] == p
        @test r[r[!, :tick] .== (n+1)*u"hr", :b] == p .* n
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
        N = names(r)
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
