# Run with the documentation environment:
#   julia --project=docs docs/checks/learning.jl
# Execute the actual learning-page examples, then check their numerical results.
# Generated inspection images are confined to a temporary directory.

using Cropbox
using DataFrames
using Test

source = normpath(joinpath(@__DIR__, "..", "src"))
pages = [
    "index.md",
    "tutorials/quickstart.md",
    "tutorials/growth.md",
    "concepts/overview.md",
    "guide/system.md",
    "concepts/lifecycle.md",
    "howto/inspection.md",
]
examples = Dict{String, Module}()

mktempdir() do temporary
    cd(temporary) do
        for page in pages
            path = joinpath(source, page)
            text = read(path, String)
            for block in eachmatch(r"^```@example\s+(\S+)\n(.*?)^```"ms, text)
                name, code = block.captures
                scope = get!(examples, name) do
                    Module(Symbol("Docs_", name))
                end
                Base.include_string(scope, code, path)
            end
        end
    end
end

@testset "First growth simulation" begin
    result = examples["quickstart"].result
    @test nrow(result) == 201
    @test names(result) == ["time", "biomass"]
    @test first(result.biomass) == 0.25u"g"
    @test 280u"g" < last(result.biomass) < 300u"g"
    @test all(diff(result.biomass) .> 0u"g")
    @test last(result.time) == 200u"d"
end

@testset "Growth scenarios approach the same final biomass" begin
    scope = examples["quickstart"]
    endpoints = map([0.03, 0.05, 0.07]) do r
        result = simulate(scope.LogisticGrowth;
            config = @config(scope.config, scope.LogisticGrowth => :growth_rate => r),
            stop = 400u"d",
            target = :biomass,
        )
        @test nrow(result) == 401
        @test 297u"g" < last(result.biomass) <= 300u"g"
        last(result.biomass)
    end
    @test issorted(endpoints)
end

@testset "Reading an instance value" begin
    s = examples["systemguide"].s
    @test s.r' == value(s.r) == 0.07u"d^-1"
    @test s.W' == 0.25u"g"
    @test s.context.clock.time' == 0u"d"
end

@testset "Illustrative observation comparison" begin
    scope = examples["logistic"]
    @test nrow(scope.observations) == 4
    @test issubset(scope.observations.t, scope.result.t)
    rmse = evaluate(scope.LogisticGrowth, scope.observations;
        config = scope.config,
        index = :t,
        target = :W,
        stop = 300u"d",
        metric = :rmse,
    )
    @test 0u"g" < rmse < 2u"g"
end

@testset "Named rate and threshold" begin
    result = examples["concepts"].result
    @test last(result.ready)
    @test !result.ready[end - 1]
    @test last(result.W) >= 270u"g"
    @test all(result.g .> 0u"g/d")
end

@testset "Fresh simulations and reused instances" begin
    scope = examples["lifecycle"]
    @test first(scope.result.W) == 0.25u"g"
    @test first(scope.result.time) == 0u"d"
    @test last(scope.result.ready)
    @test scope.s2.W' == last(scope.result2.W)
end

@testset "One point per parameter response" begin
    result = examples["inspectflow"].responses
    @test nrow(result) == 7
    @test length(unique(result.rate)) == 7
    @test all(result.time .== 2u"hr")
    @test all(isapprox.(result.mass, result.rate .* 2u"hr"))
end
