@system FlowWeather begin
    Tmin => [4, 6]   ~ preserve::int[]
    Tmax => [16, 20] ~ preserve::int[]
end

@system FlowGrowth(Controller) begin
    met(context): weather ~ ::FlowWeather

    i: day => error("set day in config") ~ preserve::int(parameter)
    valid  => [true, false]              ~ preserve::bool[]

    Tmean(lo = weather.Tmin, hi = met.Tmax, i, day) => (lo[i] + hi[day]) / 2 ~ track(when = valid[day[]])

    total(Tmean)                           ~ accumulate
    done(done, total) => done || total > 0 ~ flag
end

@system FlowRoot(Controller) begin
    lo => 0 ~ preserve
    hi => 2 ~ preserve

    root => root^2 - 2 ~ solve(lower = lo, upper = hi)
end

@system FlowCall(Controller) begin
    k: gain        => 2        ~ preserve(parameter)
    f(gain; x)     => gain * x ~ call
    g(f; x): scale => f(x) + 1 ~ call

    out(h = scale)   => h(3.0)            ~ track
    available(scale) => !isnothing(scale) ~ flag
    direct(v = scale(gain[]))             ~ track
end

@testset "flow" begin
    plot = visualize(FlowGrowth; kind = :flow)

    @testset "update order and feedback" begin
        p = visualize(FlowGrowth, :total; kind = :flow, depth = 0).plan
        steps = sort(Cropbox.dependency(FlowGrowth))
        @test [e.order for e in p.events] == findall(n -> n.info.name == :total, steps)
        @test [(e.operation, e.code) for e in p.events] == [(:state, ""), (:rate, "Tmean")]
        @test p.ports == ["Tmean"]

        c = only(c for c in p.carries if c.slot == :rate)
        @test (p.events[c.from].operation, p.events[c.to].operation) == (:rate, :state)
        @test any(c -> c.name == "done" && c.slot == :value, plot.plan.carries)
    end

    @testset "declared reads" begin
        reads = only(e.reads for e in plot.plan.events if e.node.info.name == :Tmean)
        @test sort([r.name for r in reads if r.role == :data]) == ["i", "met.Tmax", "met.Tmin"]
        @test sort([r.name for r in reads if r.role == :when]) == ["i", "valid"]

        p = visualize(FlowRoot, :root; kind = :flow, depth = 0).plan
        @test Set((r.name, r.role) for r in only(p.events).reads) == Set([("lo", :lower), ("hi", :upper)])
    end

    @testset "bound call inputs" begin
        p = visualize(FlowCall, [:out, :available, :direct]; kind = :flow, depth = 0).plan
        @test [(b.node.info.name, only(b.reads).name) for b in p.bindings] == [(:f, "k"), (:g, "f")]
        @test Dict(e.node.info.name => sort([r.name for r in e.reads]) for e in p.events) == Dict(:out => ["g"], :available => ["g"], :direct => ["g", "k"])
        @test Set(p.ports) == Set(["f", "g", "k"])
    end

    @testset "display and export" begin
        @test occursin("Tmean", repr(MIME"text/plain"(), plot))
        svg = MIME"image/svg+xml"()
        @test showable(svg, plot)
        @test occursin("<svg", repr(svg, plot))
        mktempdir() do dir
            pdf = Cropbox.writeimage(joinpath(dir, "flow.pdf"), plot)
            @test read(pdf, 5) == b"%PDF-"
        end
    end
end
