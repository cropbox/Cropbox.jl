using DataFrames

plotbounds(p) = begin
    haskey(p.opt, :axis) || return (p.opt[:xlim], p.opt[:ylim])
    r = p.opt[:axis].finallimits[]
    Tuple(zip(minimum(r), maximum(r)))
end

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
        bounds = plotbounds(p)
        @test Cropbox.detectbackend(p) == backend
        @test visualize!(p, 120u"minute", 2000u"mg", "An = 10\ngs = 0.2"; color = :red) === p
        @test plotbounds(p) == bounds

        output = backend == :Makie ? only(p.opt[:axis].scene.plots[end].text[]) : repr(MIME"text/plain"(), p[])
        @test occursin("An = 10", output)
        @test occursin("gs = 0.2", output)
        for (kind, value) in ((:hline, 2000u"mg"), (:vline, 120u"minute"))
            @test visualize!(p, value; kind) === p
            @test p.opt[:Xs][end] == [2]
            @test plotbounds(p) == bounds
            @test_throws ArgumentError visualize(value; kind, backend)
        end
        @test_throws ArgumentError visualize!(p, [0, 4], [1, 3]; backend = backend == :Makie ? :UnicodePlots : :Makie)
        @test_throws ArgumentError visualize!(p, [0, 4], [1, 3]; linestyle = :unknown)
        @test_throws ArgumentError visualize!(p, 2, 2, "text"; align = :unknown)
    end

    @testset "date annotations" for backend in (:Makie, :UnicodePlots)
        for t in (Cropbox.Dates.Date(2026, 1, 1), Cropbox.Dates.DateTime(2026, 1, 1))
            p = visualize([t, t + Cropbox.Dates.Day(2)], [1, 3]; backend, kind = :line)
            @test visualize!(p, t + Cropbox.Dates.Day(1), 2, "event") === p
            output = backend == :Makie ? only(p.opt[:axis].scene.plots[end].text[]) : repr(MIME"text/plain"(), p[])
            @test occursin("event", output)
            backend == :Makie && show(IOBuffer(), MIME"image/png"(), p)
        end
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
        @test occursin("<svg", repr(MIME"image/svg+xml"(), p))

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

    @testset "UnicodePlots scatterline" begin
        p = visualize([0, 1, 2], [0, 1, 0]; backend = :UnicodePlots, kind = :scatterline, name = "model")
        marker = string(Cropbox.UnicodePlots.char_marker(:circle))
        output = repr(MIME"text/plain"(), p[])
        @test occursin(marker, output)
        @test count("model", output) == 1
        @test p.opt[:names] == ["model"]
        @test visualize!(p, [0, 1, 2], [1, missing, 1]; kind = :scatterline) === p
        @test length(p.opt[:Ys]) == 2
        dates = [Cropbox.Dates.Date(2026, 1, d) for d in 1:3]
        q = visualize(dates, [0, 1, 0]; backend = :UnicodePlots, kind = :scatterline)
        @test occursin(marker, repr(MIME"text/plain"(), q[]))
    end

    @testset "single date" begin
        for t in (Cropbox.Dates.Date(2026, 1, 1), Cropbox.Dates.DateTime(2026, 1, 1))
            p = visualize(DataFrame(time = [t], y = [1]), :time, :y; backend = :Makie)
            xlim, _ = plotbounds(p)
            @test xlim[1] < xlim[2]
            @test occursin("<svg", repr(MIME"image/svg+xml"(), p))
            visualize!(p, [t + Cropbox.Dates.Day(2)], [2])
            xlim, _ = plotbounds(p)
            lasttime = Cropbox.Makie.convert_dim_value(p.opt[:axis], 1, t + Cropbox.Dates.Day(2))
            @test xlim[1] <= lasttime <= xlim[2]
            @test length(p.opt[:Xs]) == 2
            @test occursin("<svg", repr(MIME"image/svg+xml"(), p))
        end
    end

    @testset "UnicodePlots categories" begin
        p = visualize([0, 1], [:a, :b]; backend = :UnicodePlots, kind = :step, ycat = [:a, :b, :c])
        @test visualize!(p, [0, 1], [:b, :c]; kind = :step) === p
        @test p.opt[:ycat] == [:a, :b, :c]
        @test p.opt[:Ys] == [[1, 2], [2, 3]]
        @test_throws ArgumentError visualize!(p, [0, 1], [:a, :d]; kind = :step)
        @test length(p.opt[:Ys]) == 2

        df = DataFrame(x = [0, 1, 0, 1], y = [:a, :b, :b, :c], run = [1, 1, 2, 2])
        q = visualize(df, :x, :y; backend = :UnicodePlots, kind = :step, group = :run)
        @test q.opt[:ycat] == [:a, :b, :c]
        @test q.opt[:Ys] == [[1, 2], [2, 3]]
        @test occursin("c", repr(MIME"text/plain"(), q[]))
        @test visualize([0, 1], [false, false]; backend = :UnicodePlots, kind = :step).opt[:ycat] == [false, true]
    end

    @testset "UnicodePlots dates" for T in (Cropbox.Dates.Date, Cropbox.Dates.DateTime)
        X = [T(2026, 1, 1), T(2026, 1, 3)]
        p = visualize(DataFrame(time = X, y = [0, 2]), :time, :y; backend = :UnicodePlots)
        @test visualize!(p, [T(2026, 1, 2)], [1]) === p
        @test p.opt[:Xs] == [X, [T(2026, 1, 2)]]
        output = repr(MIME"text/plain"(), p[])
        @test all(t -> occursin(string(t), output), X)
    end

    @testset "constant and missing values" for backend in (:Makie, :UnicodePlots)
        for (Y, lim) in (([1.0, missing], (0, 2)), ([1.5, missing], (1, 2)),
            (Union{Missing,Float64}[missing, missing], (-1, 1)), ([1u"g", missing], (0, 2)))
            p = visualize([0, 1], Y; backend)
            if backend == :Makie
                _, ylim = plotbounds(p)
                @test all(isfinite, ylim)
                @test all(v -> ylim[1] <= v <= ylim[2], skipmissing(Cropbox.deunitfy(Y)))
            else
                @test p.opt[:ylim] == lim
            end
            @test isequal(coalesce.(p.opt[:Ys][1], NaN), coalesce.(Cropbox.deunitfy(Y), NaN))
            backend == :Makie && show(IOBuffer(), MIME"image/png"(), p)
        end
    end

    @testset "non-finite limits" begin
        @test Cropbox.findlim([NaN, -Inf, 1.5, Inf, missing]) == (1, 2)
        @test_throws ArgumentError Cropbox.findlim([NaN, Inf])
        obs = DataFrame(year = 2020:2022, doy = [20., 21., 22.]u"d")
        est = DataFrame(year = 2020:2022, doy = [20., NaN, 22.]u"d")
        unreached = DataFrame(year = 2020:2022, doy = fill(NaN*u"d", 3))
        for backend in (:Makie, :UnicodePlots)
            p = visualize(est, :year, :doy; backend, kind = :line)
            @test all(isfinite, last(plotbounds(p)))
            @test isequal(p.opt[:Ys][1], [20., NaN, 22.])
            backend == :UnicodePlots && @test allequal(p[].graphics.grid)
            backend == :Makie && show(IOBuffer(), MIME"image/png"(), p)

            q = visualize(obs, est, :doy; index = :year, backend)
            @test plotbounds(q) == ((20, 22), (20, 22))
            @test isequal(q.opt[:Ys][1], [20., NaN, 22.])
            @test all(isnan, visualize(obs, unreached, :doy; index = :year, backend).opt[:Ys][1])
            @test_throws ArgumentError visualize(unreached, unreached, :doy; index = :year, backend)
            backend == :Makie && show(IOBuffer(), MIME"image/png"(), q)

            p = visualize(unreached, :year, :doy; backend, ylim = (1, 366))
            @test last(plotbounds(p)) == (1, 366)
            @test all(isnan, p.opt[:Ys][1])
        end
        @test_throws ArgumentError visualize(unreached, :year, :doy; backend = :UnicodePlots)
        @test isequal(est.doy, [20., NaN, 22.]u"d")
    end

    @testset "series option lengths" begin
        @system VisualizeOptions(Controller) begin
            x => 1 ~ preserve(parameter)
            y(x) => 2x ~ track
            z(x) => 3x ~ track
        end
        df = DataFrame(x = [1, 2], y = [2, 4], z = [3, 6])
        systems = [VisualizeOptions, VisualizeOptions]
        maps = [(; system = S) for S in systems]
        group = VisualizeOptions => :x => [1, 2]
        @testset "$backend" for backend in (:Makie, :UnicodePlots)
            cases = (
                arrays = opts -> visualize(df.x, [df.y, df.z]; backend, opts...),
                dataframe = opts -> visualize(df, :x, [:y, :z]; backend, opts...),
                systems = opts -> visualize(systems, :x, :y; backend, opts...),
                grouped = opts -> visualize(VisualizeOptions, :x, :y; group, backend, opts...),
                overlay = opts -> visualize(df, systems, :x, :y; backend, opts...),
                comparison = opts -> visualize(df, df, [:y, :z]; index = :x, backend, opts...),
                model = opts -> visualize(df, VisualizeOptions, [:y, :z]; index = :x, backend, opts...),
                maps = opts -> visualize(df, maps, :y; index = :x, backend, opts...),
            )
            @testset "$name" for (name, f) in pairs(cases)
                for n in (0, 1, 3), opts in ((; names = fill("series", n)), (; colors = fill(:red, n)))
                    @test_throws ArgumentError f(opts)
                end
                @test length(f((; names = ["a", "b"], colors = [:red, :blue])).opt[:Ys]) ==
                    (name in (:comparison, :model, :maps, :overlay) ? 3 : 2)
            end
            p = visualize(VisualizeOptions, :x, :y; group, names = :x, backend)
            @test length(p.opt[:Ys]) == 2
            for opts in ((; names = ["short"]), (; colors = [:red]))
                @test_throws ArgumentError visualize!(p, df, :x, [:y, :z]; opts...)
                @test length(p.opt[:Ys]) == 2
            end
            @test_throws ArgumentError visualize(df.x, [df.y, df.z]; names = ["short"], legend = false, backend)
        end
    end

    @testset "grouped data" begin
        @system VisualizeGrowth(Controller) begin
            a => 0.05 ~ preserve(parameter)

            x(a, x) => a * x ~ accumulate(init = 1)
        end
        group = VisualizeGrowth => :a => [0.05, 0.1, 0.2]
        df = simulate(VisualizeGrowth; configs = @config(!group), stop = 20, verbose = false)
        df.site = fill("A", nrow(df))
        df.y = 2df.x
        before = copy(df)
        @testset "$backend" for backend in (:Makie, :UnicodePlots)
            p = visualize(VisualizeGrowth, :time, :x; group, stop = 20, kind = :line, backend)
            q = visualize(df, :time, :x; group = :a, kind = :line, backend)
            @test p.opt[:Ys] == q.opt[:Ys]
            @test plotbounds(p) == plotbounds(q)
            _, ylim = plotbounds(q)
            @test ylim[1] <= minimum(df.x) <= maximum(df.x) <= ylim[2]
            @test q.opt[:legend] == "a"
            @test q.opt[:names] == ["0.05", "0.1", "0.2"]
            r = visualize(view(df, :, :), :time, :x; group = [:site, :a], backend)
            @test r.opt[:Ys] == q.opt[:Ys]
            r = visualize(df, :time, [:x, :y]; group = "a", colors = [:red, :blue, :red, :blue, :red, :blue], backend)
            @test length(r.opt[:Ys]) == 6
            _, ylim = plotbounds(r)
            @test ylim[1] <= minimum(df.x) <= maximum(df.y) <= ylim[2]
            r = visualize(reverse(df), :time, :x; group = :a, ylim = (0, 10), backend)
            @test r.opt[:ylim] == (0, 10)
            @test_throws ArgumentError visualize(df, :time, :x; group = :a, names = ["short"], backend)
            @test_throws ArgumentError visualize(df[1:0, :], :time, :x; group = :a, backend)
            @test_throws ArgumentError visualize!(q, df, :time, :x; group = :a, colors = [:red])
            @test length(q.opt[:Ys]) == 3
            @test isequal(df, before)
            backend == :Makie && show(IOBuffer(), MIME"image/png"(), q)
        end
    end

    @testset "appended limits" begin
        p = visualize([0, 1]u"hr", [0, 1]u"g"; backend = :Makie)
        bounds = plotbounds(p)
        visualize!(p, 100u"g"; kind = :hline)
        visualize!(p, 100u"hr", 100u"g", "outside")
        @test plotbounds(p) == bounds
        @test visualize!(p, [0, 120]u"minute", [-1000, 5000]u"mg") === p
        xlim, ylim = plotbounds(p)
        @test xlim[1] <= 0 <= 2 <= xlim[2]
        @test ylim[1] <= -1 <= 5 <= ylim[2]
        @test p.opt[:axis].limits[] == (nothing, nothing)

        q = visualize([0, 1], [0, 1]; ylim = (0, 2), backend = :Makie)
        visualize!(q, [0, 3], [0, 10])
        @test last(plotbounds(q)) == (0, 2)
        @test first(plotbounds(q))[2] >= 3
        visualize!(q, [0, 4], [0, 20]; ylim = (0, 15))
        @test last(plotbounds(q)) == (0, 15)
        visualize!(q, [0, 2], [0, 30])
        @test last(plotbounds(q)) == (0, 15)
        @test first(plotbounds(q))[2] >= 4
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

    @testset "UnicodePlots heatmap grids" begin
        df = DataFrame(x = [2, 1, 2], y = [2, 1, 1], z = [missing, 2., 4.])
        @test isequal(last(Cropbox.makegrid(df.x, df.y, df.z)), [2 NaN; 4 NaN])
        @test_throws ArgumentError visualize(vcat(df, df), :x, :y, :z; backend = :UnicodePlots)
        for d in (df, df[2:2, :])
            p = visualize(d, :x, :y, :z; backend = :UnicodePlots, aspect = 2)
            @test size(p[].graphics.grid) == (length(unique(d.y)), length(unique(d.x)))
            @test !isempty(repr(MIME"text/plain"(), p[]))
            @test all(isfinite, p[].cmap.lim)
        end
        irregular = DataFrame(x = [0, 1, 3], y = [0, 0, 0], z = [1, 2, 3])
        @test_throws ArgumentError visualize(irregular, :x, :y, :z; backend = :UnicodePlots)
    end

    @testset "UnicodePlots contours" begin
        df = DataFrame(x = repeat([0, 1, 3], inner = 2), y = repeat([0, 2], 3), z = 0:5)
        p = @test_logs visualize(df, :x, :y, :z; backend = :UnicodePlots, kind = :contour, zlim = (0, 10), legend = false)
        @test p[].graphics isa Cropbox.UnicodePlots.BrailleCanvas
        @test p[].cmap.lim == (0, 10)
        @test !p[].cmap.bar
        @test !isempty(repr(MIME"text/plain"(), p[]))
        @test_logs (:warn, r"unsupported contour interval") visualize(df, :x, :y, :z; backend = :UnicodePlots, kind = :contour, zgap = 2)
        @test_throws ArgumentError visualize(df[1:2, :], :x, :y, :z; backend = :UnicodePlots, kind = :contour)
    end

    @testset "heatmap limits and colorbar" begin
        df = DataFrame(x=[1, 1, 2, 2], y=[1, 2, 1, 2], z=[2., 3., 4., 5.])
        for backend in (:Makie, :UnicodePlots)
            p = visualize(view(df, [4, 1, 3, 2], :), :x, :y, :z; backend)
            @test p.opt[:Z] == df.z[[4, 1, 3, 2]]
            @test p.opt[:zlim] == (2, 5)
        end
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
