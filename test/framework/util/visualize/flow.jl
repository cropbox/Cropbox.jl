@system FlowWeather begin
    temperature => error("inspection must not run the model") ~ track
end

@system FlowExample(Controller) begin
    weather(context) ~ ::FlowWeather
    base => 5 ~ preserve(parameter)
    initial => 0 ~ preserve
    rate(T = weather.temperature, base) => max(T - base, 0) ~ track
    total(rate) ~ accumulate(init = initial)
    ready(total) => total > 10 ~ flag(once)
    saved(total) ~ remember(when = ready)
    conditional(rate) ~ track(when = ready, init = base)
    gated(rate) => rate > 0 ~ flag(when = ready)
    latched(rate) => rate > 0 ~ flag(once, when = ready)
    capture_rate(rate) ~ capture(when = ready)
    input => [1, 2, 3] ~ drive
    counter ~ advance
end

@system FlowFixed begin
    parameter => 1 ~ preserve(parameter)
end

@system FlowFeedback(Controller) begin
    idx => 1 ~ preserve::Int(parameter)
    mask(idx) => [false, true] ~ preserve::Vector{Bool}
    pick => true ~ flag(when = mask[idx[]])
    toggle(toggle) => !toggle ~ flag
    latched(latched) => !latched ~ flag(once)
    tracked(tracked) => !tracked ~ track::Bool(init = false)
end

@system FlowSpecial(Controller) begin
    lower => 0 ~ preserve
    upper => 2 ~ preserve
    root(root) => root^2 - 2 ~ bisect(lower = lower, upper = upper)
    bounded(bounded) => bounded^2 - 2 ~ bisect(min = lower, max = upper)
    solution => solution^2 - 2 ~ solve(lower = lower, upper = upper)
    area(; x) => x^2 ~ integrate(from = lower, to = upper)
    children => produce(FlowFixed) ~ produce::FlowFixed[]
end

@system FlowPrivateA begin
    _a => 1 ~ preserve
    b(_a) => begin
        delta = a + 1
        delta^2
    end ~ track
end
@system FlowPrivateB begin
    _a => 2 ~ preserve
    c(_a) ~ track
end
@system FlowPrivate(FlowPrivateA, FlowPrivateB)

@system FlowDetails(Controller) begin
    elapsed(time = context.clock.time) ~ track(u"hr")
    rate => 2 ~ preserve(u"g/hr")
    enabled => true ~ flag
    restart => false ~ flag
    mask => [true, false] ~ preserve::Vector{Bool}
    indexed(enabled) ~ flag(once = false, when = mask[1])
    amount(rate) ~ accumulate(time = elapsed, u"g", when = enabled, reset = restart)
    captured(rate) ~ capture(time = elapsed, u"g")
    child => produce(FlowFixed) ~ produce::FlowFixed(when = enabled)
    solution => solution^2 - 2 ~ solve
    smallest => smallest^2 - 2 ~ solve(pick = :minimum)
    root(root) => root^2 - 2 ~ bisect(lower = 0, upper = 2, maxiter = 25, tol = 0.001)
    branch(rate) => if rate > 0u"g/hr"
        rate
    else
        zero(rate)
    end ~ track(u"g/hr")
end

@testset "flow" begin
    d = Cropbox.dependency(FlowExample)
    plan = Cropbox.flowplan(FlowExample, d)
    @test issorted([e.order for e in plan.events])
    @test "weather.temperature" in plan.ports
    @test all(e -> e.node.info.name ∉ (:context, :config, :base), plan.events)
    total = filter(e -> e.node.info.name == :total, plan.events)
    @test getproperty.(total, :operation) == [:state, :rate]
    @test isempty(total[1].code) && total[1].note == "accumulate"
    @test total[2].code == "rate" && total[2].note == "accumulate · save rate"
    @test any(c -> c.name == "total" && c.slot == :rate, plan.carries)
    gated = only(filter(e -> e.node.info.name == :gated, plan.events))
    @test (name = "ready", role = :when) in gated.reads
    @test gated.code == "rate > 0" && gated.badges == ["when = ready"]
    latched = only(filter(e -> e.node.info.name == :latched, plan.events))
    @test isempty(latched.note) && latched.badges == ["once", "when = ready"]
    @test isempty(only(filter(e -> e.node.info.name == :rate, plan.events)).note)
    driver = only(filter(e -> e.node.info.name == :input, plan.events))
    @test isempty(driver.reads) && driver.note == "drive · read input"

    selected = Cropbox.selectiondependency(d, [:total]; depth = 0)
    slice = Cropbox.flowplan(FlowExample, d; selected)
    @test [e.order for e in slice.events] == [e.order for e in total]
    @test slice.ports == ["rate"]
    @test isempty(Cropbox.flowplan(FlowFixed, Cropbox.dependency(FlowFixed)).events)
    special = Cropbox.flowplan(FlowSpecial, Cropbox.dependency(FlowSpecial))
    integral = only(filter(e -> e.node.info.name == :area, special.events))
    @test Set(r.name for r in integral.reads) == Set(("lower", "upper"))
    @test all(c -> c.name != "area", special.carries)
    solution = only(filter(e -> e.node.info.name == :solution, special.events))
    @test Set(r.name for r in solution.reads) == Set(("lower", "upper"))
    @test occursin("lower = lower", solution.code) && occursin("upper = upper", solution.code)
    root = only(filter(e -> e.node.info.name == :root, special.events))
    @test Cropbox.flowphase(root.node) == :main
    @test !occursin("maxiter", root.code) && !occursin("tol", root.code)
    bounded = filter(e -> e.node.info.name == :bounded, special.events)
    @test Cropbox.flowphase.(getproperty.(bounded, :node)) == [:pre, :main]
    @test first(bounded).code == "min = lower; max = upper"
    @test !occursin("lower =", last(bounded).code)
    details = Cropbox.flowplan(FlowDetails, Cropbox.dependency(FlowDetails))
    event(name, phase = :main) = only(filter(e -> e.node.info.name == name &&
        Cropbox.flowphase(e.node) == phase, details.events))
    @test event(:solution).code == "solution ^ 2 - 2"
    @test occursin("pick = :minimum", event(:smallest).code)
    @test occursin("maxiter = 25; tol = 0.001", event(:root).code)
    for name in (:amount, :captured)
        @test event(name).code == "time = elapsed"
        @test (name = "elapsed", role = :time) in event(name).reads
    end
    @test isempty(event(:amount).badges)
    rate = event(:amount, :post)
    @test rate.code == "rate" && rate.badges == ["when = enabled", "reset = restart"]
    @test (name = "restart", role = :reset) in rate.reads
    @test isempty(event(:child).code) && isempty(event(:child).badges) && event(:child).note == "produce · update child"
    queued = event(:child, :post)
    @test queued.code == "produce(FlowFixed)" && queued.note == "produce · queue child"
    @test queued.badges == ["when = enabled"] && any(contains("only if empty"), details.hints)
    @test !any(contains("only if empty"), special.hints)
    @test isempty(event(:branch).badges)
    @test event(:indexed).badges == ["when = mask[1]"]
    private = Cropbox.flowplan(FlowPrivate, Cropbox.dependency(FlowPrivate))
    @test "FlowPrivateA._a" in values(private.labels)
    @test "FlowPrivateB._a" in values(private.labels)
    @test all(e -> !occursin("__Flow", e.code), private.events)
    block = only(filter(e -> e.node.info.name == :b, private.events))
    @test occursin("(delta = a + 1; delta ^ 2)", block.code)
    @test !occursin("begin", block.code)
    @test occursin("  a  b  ", Cropbox.flowtext(:("  a  b  ")))
    @test Cropbox.flowwrap("s ← \"a  b\"") == "s ← \"a  b\""
    @test Cropbox.flowwrap("if ok\n    a\nend") == "if ok\n    a\nend"
    @test_throws ArgumentError Cropbox.flowrule(Val(:Unknown), first(total).node.info, :main)

    @testset "feedback and indexed reads" begin
        p = visualize(FlowFeedback; kind = :flow).plan
        @test sort([(c.name, c.slot) for c in p.carries]) ==
            [("latched", :value), ("toggle", :value), ("tracked", :value)]
        p = visualize(FlowFeedback, :pick; kind = :flow, depth = 0).plan
        @test p.ports == ["idx", "mask"]
        @test all(r -> r.role == :when, only(p.events).reads)
        @test Cropbox.flowreferences(:(records[1 + i[], j[]].leaf)) == ["records.leaf", "i", "j"]

        s = instance(FlowFeedback)
        b = s.toggle[]
        update!(s)
        @test s.toggle[] == s.tracked[] == !b
        @test [instance(FlowFeedback; config = :FlowFeedback => :idx => i).pick[] for i in 1:2] == [false, true]
    end

    @testset "state tags" begin
        controls = Dict(:Track => (:override, :skip), :Flag => (:override, :parameter, :once),
            :Bring => (:override,), :Produce => (:single,), :Solve => (:pick,))
        # Construction, declaration metadata, and unit conversions omitted from update notes.
        excluded = Dict(
            :Accumulate => (:timeunit,), :Capture => (:unit, :timeunit),
            :Advance => (:init, :step, :unit), :Drive => (:unit, :from, :by, :parameter, :override),
            :Track => (:extern, :ref), :Flag => (:extern,), :Remember => (:init,),
            :Bring => (:parameters,), :Produce => (), :Solve => (), :Bisect => (:evalunit,),
            :Integrate => (:unit,), :Wrap => (), :Hold => (), :Call => (:unit,),
            :Preserve => (:unit, :optional, :parameter, :override, :extern, :ref, :min, :max, :round),
            :Provide => (:index, :init, :step, :autounit, :parameter),
            :Interpolate => (:unit, :knotunit, :reverse, :parameter),
            :Tabulate => (:unit, :rows, :columns, :parameter),
        )
        fallback = which(Cropbox.flowrule, (Val{:Unknown}, Cropbox.VarInfo, Symbol))
        template = first(total).node.info
        for m in methods(Cropbox.supportedtags)
            state = last(m.sig.parameters)
            state == Val && continue
            @test which(Cropbox.flowrule, (state, Cropbox.VarInfo, Symbol)) != fallback
            info = Cropbox.@set template.state = state.parameters[1]
            info = Cropbox.@set info.tags = merge(info.tags, Dict(:when => :ready, :reset => :ready))
            rules = filter(!isnothing, [Cropbox.flowrule(state(), info, phase) for phase in (:pre, :main, :post)])
            reads = Set(tag for rule in rules for tag in rule.tags)
            supported = Set(Cropbox.supportedtags(state()))
            @test reads ⊆ supported
            @test union(reads, get(controls, info.state, ()), excluded[info.state]) == supported
        end
    end
    for p in (plan, slice, special, private, details)
        layout = Cropbox.flowlayout(p)
        @test length(layout.bounds) == length(p.events) + 1
        @test all(i -> layout.bounds[i] < layout.ys[i] < layout.bounds[i+1], eachindex(p.events))
        @test all(c -> last(first(c.segments)) < layout.ys[c.to] &&
            layout.ys[c.from] < first(last(c.segments)), layout.carries)
    end
    neighbors = Cropbox.flowlayout(details)
    rail(name, slot) = only(c.x for c in neighbors.carries if (c.name, c.slot) == (name, slot))
    @test neighbors.xs["amount"] < rail("amount", :value) < rail("captured", :rate) < neighbors.xs["captured"]
    layout = Cropbox.flowlayout(slice)
    @test all(b-a > Cropbox.FLOW_RAIL_TAPER for c in layout.carries for (a, b) in c.segments)
    carry = only(filter(c -> c.slot == :rate, layout.carries))
    covered(y) = any(s -> first(s) <= y <= last(s), carry.segments)
    @test covered(layout.top)
    @test !covered((layout.ys[carry.to] + layout.ys[carry.from]) / 2)
    @test covered(layout.bottom - 1)
    for kind in (:railway, :schedule)
        @test_throws ArgumentError visualize(FlowExample; kind)
        @test_throws ArgumentError visualize(FlowExample, :total; kind)
    end
    @test_throws ArgumentError visualize(FlowExample; kind = :flow, style = (group = :system,))
    @test_throws ArgumentError visualize(FlowExample; kind = :flow, style = (fontsize = 0,))

    mktempdir() do dir
        for (i, plot) in enumerate((
            visualize(FlowExample; kind = :flow),
            visualize(FlowExample, :total; kind = :flow, depth = 0),
            visualize(FlowExample, :base => :ready; kind = :flow),
            visualize(FlowFixed; kind = :flow),
            visualize(FlowSpecial; kind = :flow),
            visualize(FlowPrivate; kind = :flow),
            visualize(FlowDetails; kind = :flow),
            visualize(GrowingDegree; kind = :flow, style = (fontsize = 9,)),
        ))
            @test plot isa Cropbox.FlowDiagram
            @test occursin("update operations", repr(MIME("text/plain"), plot))
            svg = Cropbox.writeimage(joinpath(dir, "$i.svg"), plot)
            @test occursin("<svg", read(svg, String))
        end
        plot = visualize(FlowExample; kind = :flow)
        @test startswith(repr(plot), "Computation flow for ")
        terminal = IOBuffer()
        display(TextDisplay(terminal), plot)
        listing = String(take!(terminal))
        @test occursin("total  # " * total[1].note, listing)
        @test occursin("latched  rate > 0  [once]  [when = ready]", listing)
        multiline = repr(MIME("text/plain"), visualize(FlowDetails; kind = :flow))
        branch = event(:branch)
        prefix = lpad(branch.order, 4) * "  branch  "
        @test occursin(prefix * replace(branch.code, '\n' => "\n" * " "^length(prefix)), multiline)
        @test showable(MIME("text/plain"), plot)
        @test showable(MIME("image/svg+xml"), plot)
        @test !showable(MIME("application/json"), plot)
        @test occursin("<svg", repr(MIME("image/svg+xml"), plot))
        pdf = Cropbox.writeimage(joinpath(dir, "flow.pdf"), plot)
        @test read(pdf)[1:4] == collect(codeunits("%PDF"))
        @test filesize(Cropbox.writeimage(joinpath(dir, "flow.png"), plot)) > 0
    end
end
