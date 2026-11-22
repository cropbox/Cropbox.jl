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
    extreme           => true              ~ flag(when = valid[i[]] && (met.Tmin[i[]] < 0 || met.Tmax[i[]] > 30))
end

@system FlowRoot(Controller) begin
    lo => 0 ~ preserve
    hi => 2 ~ preserve

    root => root^2 - 2 ~ solve(lower = lo, upper = hi)

    inside => true                    ~ flag(when = lo[] < root[] <= hi[])
    limit(v = inside[] ? hi[] : lo[]) ~ track(init = 0)
end

@system FlowCall(Controller) begin
    k: gain        => 1                    ~ accumulate
    f(gain; x)     => gain * x             ~ call
    g(f; x): scale => (scaled = f(x) + 1,) ~ call::NamedTuple

    out(h = scale)   => h(3.0).scaled     ~ track
    available(scale) => !isnothing(scale) ~ flag
    direct(v = scale(gain[]).scaled)      ~ track

    xs => [1.0, 2.0]              ~ preserve::Float64[]
    mapped(v = sum(map(f, xs[]))) ~ track(init = 0)
    dotted(v = sum(f.(xs[])))     ~ track(init = 0)
end

@testset "flow" begin
    plot = visualize(FlowGrowth; kind = :flow)
    term(d, w; color = false) = sprint(show, MIME"text/plain"(), d; context = IOContext(IOBuffer(), :displaysize => (24, w), :color => color))

    @testset "update order and feedback" begin
        p = visualize(FlowGrowth, :total; kind = :flow, depth = 0).plan
        steps = sort(Cropbox.dependency(FlowGrowth))
        @test [e.order for e in p.events] == findall(n -> n.info.name == :total, steps)
        @test [e.operation for e in p.events] == [:state, :rate]
        @test [(e.behavior, e.code, e.note) for e in p.events] == [("accumulate", "", ""), ("accumulate", "Tmean", "save rate")]
        @test p.ports == ["Tmean"]

        c = only(c for c in p.carries if c.slot == :rate)
        @test (p.events[c.from].operation, p.events[c.to].operation) == (:rate, :state)
        @test any(c -> c.name == "done" && c.slot == :value, plot.plan.carries)
    end

    @testset "declared reads" begin
        reads = only(e.reads for e in plot.plan.events if e.node.info.name == :Tmean)
        @test sort([r.name for r in reads if r.role == :data]) == ["i", "met.Tmax", "met.Tmin"]
        @test sort([r.name for r in reads if r.role == :when]) == ["i", "valid"]

        p = visualize(FlowGrowth, :extreme; kind = :flow, depth = 0).plan
        @test Set(r.name for r in only(p.events).reads if r.role == :when) == Set(["valid", "i", "met.Tmin", "met.Tmax"])

        inputs(n) = Set((r.name, r.role) for r in only(visualize(FlowRoot, n; kind = :flow, depth = 0).plan.events).reads)
        @test inputs(:root) == Set([("lo", :lower), ("hi", :upper)])
        @test inputs(:inside) == Set([("lo", :when), ("root", :when), ("hi", :when)])
        @test inputs(:limit) == Set([("inside", :data), ("hi", :data), ("lo", :data)])
    end

    @testset "bound call inputs" begin
        targets = [:out, :available, :direct]
        d = visualize(FlowCall, targets; kind = :flow, depth = 0)
        steps = sort(Cropbox.dependency(FlowCall))
        rows = split.(split(term(d, 32), '\n'))
        order = [n.info.name for n in steps if n.info.name in (:f, :g, targets...)]
        @test [(parse(Int, r[1]), Symbol(r[2])) for r in rows] == collect(enumerate(order))
        @test Dict(r[2] => join(r[3:end], " ") for r in rows) == Dict(
            "f" => "⇠ k", "g" => "⇠ f", "out" => "← g", "available" => "← g", "direct" => "← g, k")
        @test Set(d.plan.ports) == Set(["f", "g", "k"])
        @test occursin('╌', term(d, 100))
        for n in (:mapped, :dotted)
            p = visualize(FlowCall, n; kind = :flow, depth = 0).plan
            @test [(e.node.info.name, [r.name for r in e.reads]) for e in p.events] == [(:f, ["k"]), (n, ["f", "xs"])]
        end
        full = visualize(FlowCall; kind = :flow)
        @test occursin("<svg", repr(MIME"image/svg+xml"(), full))

        s = instance(FlowCall)
        f = s.g
        @test f(3.0).scaled == s.out[] == 1
        update!(s)
        @test f(3.0).scaled == s.out[] == 4
        @test s.mapped[] == s.dotted[] == 3
        Cropbox.store!(s.k, 2)
        @test f(3.0).scaled == 7 && s.out[] == 4
    end

    @testset "display and export" begin
        s = term(plot, 32)
        @test all(n -> occursin(n, s), ("met.Tmin", "met.Tmax", "[prev update]", "[next update]"))
        for d in (plot, visualize(FlowGrowth, :total; kind = :flow, depth = 0))
            main, post = findall(e -> e.node.info.name == :total, d.plan.events)
            out = term(d, 120)
            @test occursin("← (total, #$post) [prev update]", out) && occursin("→ #$main [next update]", out)
        end
        @test maximum(textwidth, split(s, '\n')) <= 32
        colored = term(plot, 32; color = true)
        @test occursin('\e', colored) && replace(colored, r"\e\[[\d;]*m" => "") == s
        svg = MIME"image/svg+xml"()
        expr = "if β[i[]] ≥ 0\n    β[i[]] + 1.5\nend"
        @test join(String.(Cropbox.flowsyntax(expr)), '\n') == expr
        @test showable(svg, plot)
        @test occursin("<svg", repr(svg, plot))
        emptyflow = visualize(FlowWeather; kind = :flow)
        @test isempty(emptyflow.plan.events) && occursin("<svg", repr(svg, emptyflow))
        mktempdir() do dir
            pdf = Cropbox.writeimage(joinpath(dir, "flow.pdf"), plot)
            @test read(pdf, 5) == b"%PDF-"
        end
    end
end
