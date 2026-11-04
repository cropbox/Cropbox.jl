using DataFrames

@testset "visualize" begin
    withenv("NJS_VERSION" => "test") do
        @test Cropbox.detectbackend(visualize([0, 1], [0, 1])) == :Makie
    end
    @test_throws ArgumentError visualize([0, 1], [0, 1]; backend = :Gadfly)

    @testset "classic fonts" begin
        p = visualize([0, 1], [0, 1]; backend = :Makie)
        ax = p.opt[:axis]
        fonts = Cropbox.Makie.theme(ax.scene, :fonts)
        @test Cropbox.Makie.to_font(fonts, :regular).family_name == "Noto Sans"
        @test Cropbox.Makie.to_font(fonts, :bold).style_name == "Bold"
        @test ax.xticklabelsize[] == ax.yticklabelsize[] == 10
        @test ax.xlabelsize[] == ax.ylabelsize[] == ax.titlesize[] == 12
    end

    @testset "$backend" for backend in (:Makie, :UnicodePlots)
        p = visualize([0, 4]u"hr", [0, 4]u"g"; kind = :line, name = "model", backend)
        @test visualize!(p, [0, 4]u"hr", [4, 0]u"g"; kind = :line, name = "reference") === p
        @test Cropbox.detectbackend(p) == backend
        @test visualize!(p, 120u"minute", 2000u"mg", "An = 10\ngs = 0.2"; color = :red) === p
        @test p.opt[:xlim] == p.opt[:ylim] == (0, 4)

        output = backend == :Makie ? only(p.opt[:axis].scene.plots[end].text[]) : repr(MIME"text/plain"(), p[])
        @test occursin("An = 10", output)
        @test occursin("gs = 0.2", output)
        for (kind, value) in ((:hline, 2000u"mg"), (:vline, 120u"minute"))
            @test visualize!(p, value; kind) === p
            @test p.opt[:Xs][end] == [2]
            @test p.opt[:xlim] == p.opt[:ylim] == (0, 4)
            @test_throws ArgumentError visualize(value; kind, backend)
        end
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

        p = visualize([0, 4], [[0, 4], [4, 0]]; backend = :Makie, kind = :line, linestyle = [:solid, :dot])
        @test p.opt[:axis].scene.plots[1].linestyle[].value == [0]
        @test p.opt[:axis].scene.plots[2].linestyle[].value == [0, 1, 3]
        @test_throws ArgumentError visualize([0, 4], [[0, 4], [4, 0]]; linestyle = [:solid])

        p = visualize([0, 4], [0, 4]; backend=:UnicodePlots, kind=:line)
        @test_logs (:warn, r"renders line style dot as a solid line") visualize!(p, [0, 4], [4, 0]; kind=:line, linestyle=:dot)
    end

    @testset "UnicodePlots colors" for color in (:red, (255, 0, 0))
        p = visualize([0, 1], [0, 1]; backend = :UnicodePlots, color)
        @test visualize!(p, [0, 1], [1, 0]; color = 1) === p
        @test p.opt[:colors] == [color, color]
    end

    @testset "single date" begin
        for t in (Cropbox.Dates.Date(2026, 1, 1), Cropbox.Dates.DateTime(2026, 1, 1))
            p = visualize(DataFrame(time = [t], y = [1]), :time, :y; backend = :Makie)
            @test p.opt[:xlim] == (t - Cropbox.Dates.Day(1), t + Cropbox.Dates.Day(1))
            @test occursin("<svg", repr(MIME"image/svg+xml"(), p))
        end
    end

    @testset "stored estimates" begin
        @system VisualizeComparison(Controller) begin
            rate => 1 ~ preserve(parameter, u"g/hr")
            a(rate) ~ accumulate(u"g")
            b(a) => 2a ~ track(u"g")
        end
        est = simulate(VisualizeComparison; target = [:a, :b], stop = 3, verbose = false)
        obs = est[[4, 2, 1], :]
        obs.time = [180, 60, 0]u"minute"
        obs.a .+= 0.1u"g"
        obs.b .+= 0.2u"g"
        obs.note = fill("observed", 3)
        est.note = fill("estimated", 4)
        before = copy(obs), copy(est)
        points(p, i = 1) = sort(collect(zip(p.opt[:Xs][i], p.opt[:Ys][i])))

        @testset "$backend" for backend in (:Makie, :UnicodePlots)
            p = visualize(obs, est, :a; index = :time, name = "saved", colors = [:red], backend)
            @test points(p) == [(0.1, 0), (1.1, 1), (3.1, 3)]
            @test p.opt[:kinds] == [:scatter, :line]
            @test p.opt[:colors][1] == :red
            @test p.opt[:xlim] == p.opt[:ylim] == (0, 4)
            @test p.opt[:Xs][end] == p.opt[:Ys][end] == [0, 4]
            q = visualize(obs, VisualizeComparison, :a; index = :time => "context.clock.time", stop = 3, backend)
            @test points(q) == points(p)
            @test visualize!(p, obs, est, :a; index = :time) === p
            @test points(p, 3) == points(p)
            q = visualize(view(obs, :, :), view(est, :, :), :a; index = :time, backend)
            @test points(q) == points(p)

            for source in (est, VisualizeComparison)
                opts = source isa DataFrame ? (; index = :time) : (; index = :time => "context.clock.time", stop = 3)
                q = visualize(obs, source, [:a, :b]; colors = [:red, :blue], backend, opts...)
                @test points(q) == points(p)
                @test points(q, 2) == [(0.2, 0), (2.2, 2), (6.2, 6)]
                @test q.opt[:colors][1:2] == [:red, :blue]
            end

            renamed = rename(obs, :time => :hour, :a => :measured)
            q = visualize(renamed, est, "measured" => "a"; index = "hour" => "time", backend)
            @test points(q) == points(p)
            maps = [(; system = VisualizeComparison),
                (; system = VisualizeComparison, config = VisualizeComparison => :rate => 2)]
            q = visualize(obs, maps, :a; index = :time => "context.clock.time", stop = 3, backend)
            @test points(q) == points(p)
            @test points(q, 2) == [(0.1, 0), (1.1, 2), (3.1, 6)]

            o = DataFrame(id = [1, 1, 2], time = [1, 1, 1]u"hr", a = [10, 10, 20])
            e = DataFrame(id = [2, 1, 3], time = [60, 60, 60]u"minute", a = [21, 11, 31])
            q = visualize(o, e, :a; index = [:id, :time], backend)
            @test points(q) == [(10, 11), (10, 11), (20, 21)]
            @test_throws ArgumentError visualize(obs, est[1:0, :], :a; index = :time, backend)
            @test isequal((obs, est), before)
        end
    end

    @testset "heatmap limits and colorbar" begin
        df = DataFrame(x=[1, 1, 2, 2], y=[1, 2, 1, 2], z=[2., 3., 4., 5.])
        @test_throws ArgumentError visualize(df, :x, :y, :z; backend = :Gadfly)
        for legend in (true, false)
            p = @test_logs visualize(df, :x, :y, :z; backend=:UnicodePlots, zlim=(0, 10), legend)
            @test p[].cmap.lim == (0, 10)
            @test p[].cmap.bar == legend
        end
        output(df) = repr(MIME"text/plain"(), visualize(df, :x, :y, :z; backend = :UnicodePlots)[]; context = :color => true)
        @test output(df) == output(df[[4, 1, 3, 2], :])
    end
end
