using DataFrames

@testset "visualize" begin
    withenv("NJS_VERSION" => "test") do
        @test Cropbox.detectbackend(visualize([0, 1], [0, 1])) == :Makie
    end
    @test_throws ArgumentError visualize([0, 1], [0, 1]; backend = :Gadfly)

    @testset "$backend" for backend in (:Makie, :UnicodePlots)
        p = visualize([0, 4]u"hr", [0, 4]u"g"; kind = :line, name = "model", backend)
        @test visualize!(p, [0, 4]u"hr", [4, 0]u"g"; kind = :line, name = "reference") === p
        @test Cropbox.detectbackend(p) == backend
        @test visualize!(p, 120u"minute", 2000u"mg", "An = 10\ngs = 0.2"; color = :red) === p
        @test p.opt[:xlim] == p.opt[:ylim] == (0, 4)

        output = backend == :Makie ? only(p.opt[:axis].scene.plots[end].text[]) : repr(MIME"text/plain"(), p[])
        @test occursin("An = 10", output)
        @test occursin("gs = 0.2", output)
        @test_throws ArgumentError visualize!(p, [0, 4], [1, 3]; backend = backend == :Makie ? :UnicodePlots : :Makie)
        @test_throws ArgumentError visualize!(p, [0, 4], [1, 3]; linestyle = :unknown)
        @test_throws ArgumentError visualize!(p, 2, 2, "text"; align = :unknown)
    end

    @testset "line style and legend position" begin
        pos = (0.1, -0.3)
        p = visualize([0, 4], [0, 4]; backend = :Makie, kind = :line, name = "model", legendpos = pos)
        keypos = p.opt[:key].layoutobservables.suggestedbbox[]
        visualize!(p, [0, 4], [4, 0]; kind = :line, name = "reference", linestyle = :dot)
        @test p.opt[:key].layoutobservables.suggestedbbox[] == keypos
        @test p.opt[:legendpos] == pos
        @test p.opt[:labels] == ["model", "reference"]
        @test p.opt[:axis].scene.plots[end].linestyle[].value == [0, 1, 3]
        @test occursin("data:image/png;base64,", repr(MIME"text/html"(), p))

        p = visualize([0, 4], [0, 4]; backend=:UnicodePlots, kind=:line)
        @test_logs (:warn, r"renders line style dot as a solid line") visualize!(p, [0, 4], [4, 0]; kind=:line, linestyle=:dot)
    end

    @testset "heatmap limits and colorbar" begin
        df = DataFrame(x=[1, 1, 2, 2], y=[1, 2, 1, 2], z=[2., 3., 4., 5.])
        @test_throws ArgumentError visualize(df, :x, :y, :z; backend = :Gadfly)
        for legend in (true, false)
            p = @test_logs visualize(df, :x, :y, :z; backend=:UnicodePlots, zlim=(0, 10), legend)
            @test p[].cmap.lim == (0, 10)
            @test p[].cmap.bar == legend
        end
    end
end
