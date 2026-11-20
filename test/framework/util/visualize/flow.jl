using InteractiveUtils: subtypes

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
    k: gain        => 1        ~ accumulate
    f(gain; x)     => gain * x ~ call
    g(f; x): scale => f(x) + 1 ~ call

    out(h = scale)   => h(3.0)            ~ track
    available(scale) => !isnothing(scale) ~ flag
    direct(v = scale(gain[]))             ~ track
end

@testset "flow" begin
    plot = visualize(FlowGrowth; kind = :flow)
    term(d, w; color = false) = sprint(show, MIME"text/plain"(), d; context = IOContext(IOBuffer(), :displaysize => (24, w), :color => color))

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

    @testset "state tags" begin
        # Supported tags used for setup or control rather than for update reads.
        other = (; Accumulate = (:timeunit,), Capture = (:unit, :timeunit), Advance = (:init, :step, :unit),
            Drive = (:unit, :from, :by, :parameter, :override), Track = (:override, :skip, :extern, :ref),
            Flag = (:override, :parameter, :once, :extern), Remember = (:init,), Bring = (:override, :parameters),
            Produce = (:single,), Solve = (:pick,), Bisect = (:evalunit,), Integrate = (:unit,),
            Preserve = (:unit, :optional, :parameter, :override, :extern, :ref, :min, :max, :round),
            Provide = (:index, :init, :step, :autounit, :parameter), Interpolate = (:unit, :knotunit, :reverse, :parameter),
            Tabulate = (:unit, :rows, :columns, :parameter))
        v = only(e.node.info for e in plot.plan.events if e.node.info.name == :Tmean)
        v = Cropbox.@set v.tags = merge(v.tags, Dict(:reset => true))
        for S in subtypes(Cropbox.State)
            (S === Cropbox.StateRef || parentmodule(S) !== Cropbox) && continue
            k = nameof(S)
            info = Cropbox.@set v.state = k
            rules = [Cropbox.flowrule(Val(k), info, phase) for phase in (:pre, :main, :post)]
            reads = unique(Symbol[t for r in rules if !isnothing(r) for t in r.tags])
            @test sort([reads; collect(get(other, k, ()))]) == sort(collect(Cropbox.supportedtags(Val(k))))
        end
        @test_throws ArgumentError Cropbox.flowrule(Val(:Unknown), v, :main)
    end

    @testset "bound call inputs" begin
        targets = [:out, :available, :direct]
        d = visualize(FlowCall, targets; kind = :flow, depth = 0)
        steps = sort(Cropbox.dependency(FlowCall))
        rows = split.(split(term(d, 32), '\n'))
        order = [(i, n.info.name) for (i, n) in enumerate(steps) if n.info.name in (:f, :g, targets...)]
        @test [(parse(Int, r[1]), Symbol(r[2])) for r in rows] == order
        @test Dict(r[2] => join(r[3:end], " ") for r in rows) == Dict(
            "f" => "⇠ k", "g" => "⇠ f", "out" => "← g", "available" => "← g", "direct" => "← g, k")
        @test Set(d.plan.ports) == Set(["f", "g", "k"])
        @test occursin('╌', term(d, 100))
        full = visualize(FlowCall; kind = :flow)
        @test occursin("<svg", repr(MIME"image/svg+xml"(), full))

        s = instance(FlowCall)
        f = s.g
        @test f(3.0) == s.out[] == 1
        update!(s)
        @test f(3.0) == s.out[] == 4
        Cropbox.store!(s.k, 2)
        @test f(3.0) == 7 && s.out[] == 4
    end

    @testset "display and export" begin
        s = term(plot, 32)
        main, post = [e.order for e in plot.plan.events if e.node.info.name == :total]
        @test all(n -> occursin(n, s), ("met.Tmin", "met.Tmax", "← (total, #$post)", "→ #$main"))
        for d in (plot, visualize(FlowGrowth, :total; kind = :flow, depth = 0))
            out = term(d, 120)
            @test occursin("← (total, #$post) [prev update]", out) && occursin("→ #$main [next update]", out)
        end
        @test maximum(textwidth, split(s, '\n')) <= 32
        colored = term(plot, 32; color = true)
        @test occursin('\e', colored) && replace(colored, r"\e\[[\d;]*m" => "") == s
        svg = MIME"image/svg+xml"()
        @test showable(svg, plot)
        @test occursin("<svg", repr(svg, plot))
        mktempdir() do dir
            pdf = Cropbox.writeimage(joinpath(dir, "flow.pdf"), plot)
            @test read(pdf, 5) == b"%PDF-"
        end
    end
end
