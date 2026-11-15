flowphase(n::VarNode) = n.step isa PreStep ? :pre : n.step isa PostStep ? :post : :main

flowlabel(n) = join(map(split(string(n), '.')) do part
    owner, name = splitcanonicalname(Symbol(part))
    isnothing(owner) ? string(name) : "$owner.$name"
end, '.')
flowtext(x) = begin
    expression = MacroTools.postwalk(x isa Expr ? Base.remove_linenums!(deepcopy(x)) : x) do a
        a isa Symbol || return a
        owner, name = splitcanonicalname(a)
        isnothing(owner) ? a : Expr(:., owner, QuoteNode(name))
    end
    parts = isexpr(expression, :block) ? expression.args : [expression]
    text = join((strip(sprint(Base.show_unquoted, p)) for p in parts), "; ")
    length(parts) > 1 ? "($text)" : text
end
flowexpression(v::VarInfo) = flowtext(
    isnothing(v.body) && length(v.args) == 1 ? last(extractfuncargpair(only(v.args))) : v.body,
)
flowdefaults(v::VarInfo) = begin
    tags = Dict{Symbol,Any}(:_type => gettag(v, :_type), :unit => gettag(v, :unit))
    updatetags!(tags, Val(v.state); kwargs=v.kwargs)
    tags
end
flowsettings(v::VarInfo, keys) = begin
    defaults = flowdefaults(v)
    ["$k = $(flowtext(gettag(v, k)))" for k in keys if hastag(v, k) &&
        (!haskey(defaults, k) || !isequal(gettag(v, k), defaults[k]))]
end
flowinterval(v::VarInfo) = isequal(gettag(v, :time), flowdefaults(v)[:time]) ?
    "Δt" : "Δ($(flowtext(gettag(v, :time))))"

"""
Describe an update phase without evaluating model expressions. State adapters
mirror `genupdate`: `equation` reads declaration arguments, `tags` lists other
direct reads, and `slots` identifies values carried to the next update.
Keep these adapters in sync with state generators; unknown states are rejected
rather than assigned guessed semantics.
"""
flowrule(operation, note; equation=false, tags=(), slots=()) = (; operation, note, equation, tags, slots)
flowrule(::Val, v, phase) = throw(ArgumentError("no computation flow description for $(v.state)"))
flowrule(::Union{Val{:Preserve},Val{:Provide},Val{:Interpolate},Val{:Call},Val{:Tabulate},Val{:Hold}}, v, phase) = nothing
flowrule(::Union{Val{nothing},Val{:Bring}}, v, phase) = istag(v, :override, :skip) ? nothing :
    flowrule(:call, "update!($(flowlabel(v.name))); internals not expanded")
flowrule(::Val{:Track}, v, phase) = istag(v, :override, :skip) ? nothing :
    flowrule(:value, "$(flowlabel(v.name)) ← $(flowexpression(v))"; equation=true,
        tags=(:when, :unit, :min, :max, :round, (hastag(v, :when) ? (:init,) : ())...))
flowrule(::Val{:Flag}, v, phase) = istag(v, :override, :parameter) ? nothing :
    flowrule(:guard, "$(flowlabel(v.name)) ← $(flowexpression(v))$(istag(v, :once) ? "; until true" : "")";
        equation=true, tags=(:when,), slots=istag(v, :once) ? (:value,) : ())
flowrule(::Val{:Remember}, v, phase) =
    flowrule(:memory, "$(flowlabel(v.name)) ← $(flowexpression(v)); once";
        equation=true, tags=(:when, :unit), slots=(:value,))
flowrule(::Val{:Accumulate}, v, phase) = begin
    n = flowlabel(v.name)
    reset = gettag(v, :reset) !== false
    if phase == :post
        note = "rate($n) ← $(flowexpression(v))"
        reset && (note *= "; reset($n) ← $(flowtext(gettag(v, :reset)))")
        flowrule(:rate, note; equation=true, tags=(:when, :reset), slots=(:rate,))
    else
        note = "$n ← $n + rate($n) * $(flowinterval(v))"
        reset && (note *= "; cached reset selects $(flowtext(gettag(v, :init)))")
        flowrule(:state, note; tags=(:time, :unit, :min, :max, (reset ? (:init,) : ())...), slots=(:value,))
    end
end
flowrule(::Val{:Capture}, v, phase) = phase == :post ?
    flowrule(:rate, "rate($(flowlabel(v.name))) ← $(flowexpression(v))";
        equation=true, tags=(:when, :time), slots=(:rate,)) :
    flowrule(:state, "$(flowlabel(v.name)) ← rate($(flowlabel(v.name))) * $(flowinterval(v))"; tags=(:time,))
flowrule(::Val{:Advance}, v, phase) = begin
    n = flowlabel(v.name)
    flowrule(:state, "$n ← counter($n); counter($n) += stored step"; slots=(:value,))
end
flowrule(::Val{:Drive}, v, phase) = flowrule(:input,
    "$(flowlabel(v.name)) ← stored array[$(flowtext(gettag(v, :tick))) - initial tick + 1]"; tags=(:tick,))
flowrule(::Val{:Produce}, v, phase) = begin
    n = flowlabel(v.name)
    text = phase == :pre ? "expose $n collection" : phase == :main ?
        "update!($n); produced systems not expanded" :
        "queue($n) ← $(flowexpression(v)); construct in next PreStage"
    phase == :post && istag(v, :single) && (text *= "; only when $n is empty")
    flowrule(:produce, text; equation=phase == :post, tags=phase == :post ? (:when,) : ())
end
flowrule(::Val{:Bisect}, v, phase) = phase == :pre ?
    flowrule(:opaque, "$(flowlabel(v.name)) ← clamp($(flowlabel(v.name)))"; tags=(:min, :max)) :
    flowrule(:opaque, "$(flowlabel(v.name)) ← bisect($(flowexpression(v))); iterations not expanded";
        equation=true, tags=(:lower, :upper, :unit, :min, :max, :maxiter, :tol))
flowrule(::Val{:Solve}, v, phase) =
    flowrule(:opaque, join(["$(flowlabel(v.name)) ← solve($(flowexpression(v)))"; flowsettings(v, (:pick,))], "; ");
        equation=true, tags=(:unit, :lower, :upper))
flowrule(::Val{:Integrate}, v, phase) =
    flowrule(:opaque, "$(flowlabel(v.name)) ← integrate($(flowexpression(v)))";
        equation=true, tags=(:from, :to))
flowrule(::Val{:Wrap}, v, phase) =
    flowrule(:opaque, "$(flowlabel(v.name)) ← $(flowexpression(v))"; equation=true)

flowreferences(x) = String[]
flowreferences(x::Symbol) = [string(x)]
flowreferences(x::Expr) = begin
    a = x.args
    if isexpr(x, :(=), :kw)
        flowreferences(last(a))
    elseif isexpr(x, :.)
        ["$p.$(last(a) isa QuoteNode ? last(a).value : last(a))" for p in flowreferences(first(a))]
    elseif isexpr(x, :ref, Symbol("'"))
        flowreferences(first(a))
    elseif isexpr(x, :call)
        args = first(a) in (:&, :|) ? a[2:end] : a[2:2]
        reduce(vcat, flowreferences.(args); init=String[])
    else
        String[]
    end
end

flowreads(d::Dependency, v::VarInfo, rule) = begin
    inputs = [rule.equation ? [(:data, a) for a in v.args] : [];
        [(tag, gettag(v, tag)) for tag in rule.tags]]
    unique([(name=replace(path, r"^[^.]+" => string(d.M[root].name)), role=role)
        for (role, x) in inputs for path in flowreferences(x)
        for root in (Symbol(first(split(path, '.'))),)
        if haskey(d.M, root) && root ∉ (:context, :config) && !istag(d.M[root], :context)])
end

flownote(v::VarInfo, rule) = begin
    operation = rule.operation
    bindings = rule.equation && !isnothing(v.body) ? ["$(flowtext(first(a.args))) = $(flowtext(last(a.args)))" for a in v.args
        if isexpr(a, :(=), :kw) && first(a.args) != last(a.args)] : String[]
    condition = if :when in rule.tags && hastag(v, :when)
        w = flowtext(gettag(v, :when))
        fallback = operation == :rate ? "0" : operation == :guard ? "false" : flowtext(gettag(v, :init, 0))
        operation in (:memory, :produce) ? "when $w" : "when $w; otherwise $fallback"
    else
        ""
    end
    limits = flowsettings(v, filter(k -> k in (:min, :max, :round, :lower, :upper, :from, :to, :maxiter, :tol), rule.tags))
    join(filter(!isempty, [rule.note; bindings; condition; limits]), "; ")
end

flowplan(S::Type{<:System}, d::Dependency; selected=d) = begin
    chosen = Set(n.info.name for n in selected.N)
    events = [(; node=n, order, operation=rule.operation, slots=rule.slots,
        reads=flowreads(d, n.info, rule), note=flownote(n.info, rule))
        for (order, n) in enumerate(sort(d))
        if n.info.name in chosen && n.info.name ∉ (:context, :config) && !istag(n.info, :context)
        for rule in (flowrule(Val(n.info.state), n.info, flowphase(n)),) if !isnothing(rule)]
    variables = [v for v in geninfos(S) if v.name in chosen &&
        v.name ∉ (:context, :config) && !istag(v, :context)]
    names = string.(getproperty.(variables, :name))
    ports = sort(setdiff(unique(r.name for e in events for r in e.reads), names))
    lanes = [names; ports]
    indices = Dict((e.node.info.name, flowphase(e.node)) => i for (i, e) in enumerate(events))
    carries = [(name=string(e.node.info.name), slot, from=i, to=indices[to])
        for (i, e) in enumerate(events)
        for slot in (e.operation == :value && any(r -> r.name == string(e.node.info.name), e.reads) ? (:value,) : e.slots)
        for to in ((e.node.info.name, :main),) if haskey(indices, to)]
    labels = Dict(n => flowlabel(n) for n in lanes)
    (; model=string(namefor(S)), lanes, labels, ports, events, carries)
end

flowwrap(text; width=72) = begin
    occursin('\n', text) && return join((flowwrap(line; width) for line in split(text, '\n')), '\n')
    lines = [""]
    for (i, word) in enumerate(split(text, ' '; keepempty=true))
        if !isempty(last(lines)) && textwidth(last(lines)) + textwidth(word) + 1 > width
            push!(lines, word)
        else
            lines[end] *= (i == 1 ? "" : " ") * word
        end
    end
    join(lines, '\n')
end

flowlayout(plan) = begin
    notes = String[flowwrap(e.note) for e in plan.events]
    angled = any(n -> textwidth(n) > 7, values(plan.labels))
    spacing = angled ? 34 : 52
    header = angled ? max(60, maximum(textwidth.(values(plan.labels)); init=0) * 5.8 + 16) : 34
    top = 48 + header
    xs = Dict(n => 52 + spacing * (i - 1) for (i, n) in enumerate(plan.lanes))
    readgroups = [unique((sign(xs[r.name]-xs[string(e.node.info.name)]), r.role == :when)
        for r in e.reads) for e in plan.events]
    above = Int[18 + 4max(0, length(g)-1) for g in readgroups]
    below = Int[max(16, 14count(==('\n'), n) + 12) for n in notes]
    heights = above .+ below
    ys = top .+ cumsum(heights) .- below
    bottom = top + sum(heights) + 18
    code = 80 + spacing * length(plan.lanes)
    width = code + max(350, maximum(textwidth.(split(join(notes, '\n'), '\n')); init=0) * 6) + 24
    height = bottom + 45
    active = [(x=xs[name], lo=top-6, hi=maximum([ys[i] for (i, e) in enumerate(plan.events)
        if string(e.node.info.name) == name || any(r -> r.name == name, e.reads)]; init=top-6)) for name in plan.lanes]
    carries = [(; c..., x=xs[c.name] + (c.slot == :rate ? -9 : 9),
        segments=((top-5, ys[c.to]), (ys[c.from], bottom))) for c in plan.carries]
    rails = [active; [(x=c.x, lo=lo, hi=hi) for c in carries for (lo, hi) in c.segments]]
    (; notes, angled, top, xs, ys, bottom, code, width, height, readgroups, active, carries, rails)
end

struct FlowDiagram{P,F<:Real}
    plan::P
    fontsize::F
end
Base.show(io::IO, ::MIME"text/plain", r::FlowDiagram) = begin
    p = r.plan
    print(io, "$(p.model): $(length(p.events)) update operations, $(length(p.lanes)) lanes")
    for e in p.events
        prefix = lpad(e.order, 4) * "  "
        print(io, '\n', prefix, replace(e.note, '\n' => "\n" * " "^length(prefix)))
    end
    print(io, "\nStatic order; initialization and nested operations are not expanded.")
end
Base.show(io::IO, r::FlowDiagram) = print(io, "Computation flow for $(r.plan.model) ($(length(r.plan.events)) operations)")
Base.showable(m::MIME, ::FlowDiagram) = Makie.backend_showable(CairoMakie.Screen, m)
Base.showable(::MIME"text/plain", ::FlowDiagram) = true
Base.show(io::IO, m::MIME, r::FlowDiagram) = show(io, m, flowdraw(r)[]; backend=CairoMakie)
writeimage(name::AbstractString, r::FlowDiagram; kw...) = writeimage(name, flowdraw(r); kw...)

flowdiagram(S::Type{<:System}, d::Dependency; selected=d, style=()) = begin
    options = (; style...)
    all(k -> k == :fontsize, keys(options)) ||
        throw(ArgumentError("flow style supports only fontsize"))
    fontsize = get(options, :fontsize, 10)
    fontsize isa Real && isfinite(fontsize) && fontsize > 0 ||
        throw(ArgumentError("fontsize must be a positive finite number"))
    FlowDiagram(flowplan(S, d; selected), fontsize)
end

flowdraw(r::FlowDiagram) = flowdraw(r.plan, flowlayout(r.plan), r.fontsize)
flowdraw(plan, layout, fontsize) = begin
    (; notes, angled, top, xs, ys, bottom, code, width, height, readgroups, active, carries, rails) = layout
    styles = (
        read=(color="#2D73A1", linewidth=0.8, linestyle=:solid),
        condition=(color="#B27A24", linewidth=0.9, linestyle=:dot),
        value=(color="#89949C", linewidth=0.65, linestyle=:solid),
        rate=(color="#258D80", linewidth=0.75, linestyle=:dashdot),
        guide=(color="#DEDEDE", linewidth=0.4, linestyle=:solid),
    )
    scale = fontsize / 10
    figure = Makie.with_theme(theme_classic()) do
        Makie.Figure(size=ceil.(Int, (width, height) .* scale), figure_padding=0, backgroundcolor=:white)
    end
    scene = figure.scene
    Makie.campixel!(scene)
    point(x, y) = Makie.Point2f(x * scale, (height - y) * scale)
    font = Makie.assetpath("fonts", "DejaVuSansMono.ttf")
    texts, paths, dots = Dict(), Dict(), Dict()
    text!(x, y, text; size=10, color="#333333", align=(:left, :center), rotation=0) =
        push!(get!(texts, (size, color, align, rotation, typeof(text)), []), (point(x, y), text))
    path!(commands; layer=2, color=styles.read.color, linewidth=styles.read.linewidth, linestyle=:solid) =
        append!(get!(paths, (layer, color, linewidth, linestyle), Makie.PathCommand[]), commands)
    line!(points; kw...) = path!([Makie.MoveTo(first(points)); Makie.LineTo.(points[2:end])]; kw...)
    dot!(x, y; layer=0, marker=:circle, size=4, color=:white) =
        push!(get!(dots, (layer, marker), []), (point(x, y), size*scale, Makie.to_color(color)))
    arrow!(x, y, direction, style=styles.read) =
        path!([Makie.MoveTo(point(x-5direction, y)), Makie.LineTo(point(x, y)),
            Makie.MoveTo(point(x-3.5direction, y-1.5)), Makie.LineTo(point(x, y)),
            Makie.LineTo(point(x-3.5direction, y+1.5))]; color=style.color, linewidth=style.linewidth)
    input = Makie.BezierPath([Makie.MoveTo(-0.5, -0.3), Makie.LineTo(0.3, -0.3),
        Makie.LineTo(0.5, 0.3), Makie.LineTo(-0.3, 0.3), Makie.ClosePath()])
    rounded = Makie.BezierPath([Makie.MoveTo(-0.3, -0.5), Makie.LineTo(0.3, -0.5),
        Makie.CurveTo(0.5, -0.5, 0.5, -0.5, 0.5, -0.3), Makie.LineTo(0.5, 0.3),
        Makie.CurveTo(0.5, 0.5, 0.5, 0.5, 0.3, 0.5), Makie.LineTo(-0.3, 0.5),
        Makie.CurveTo(-0.5, 0.5, -0.5, 0.5, -0.5, 0.3), Makie.LineTo(-0.5, -0.3),
        Makie.CurveTo(-0.5, -0.5, -0.5, -0.5, -0.3, -0.5), Makie.ClosePath()])
    text!(20, 20, plan.model; size=12)
    text!(20, 37, "one update · static order, not elapsed time"; size=8, color="#777777")
    text!(code, top-16, "operation / declared expression"; size=8, color="#777777")
    for name in plan.lanes
        x = xs[name]
        label = if occursin('.', plan.labels[name])
            prefix, leaf = String.(rsplit(plan.labels[name], '.'; limit=2))
            Makie.rich(Makie.rich(prefix; color="#888888"), Makie.rich("."; color="#BBBBBB"),
                Makie.rich(leaf; color="#333333"))
        else
            plan.labels[name]
        end
        text!(x, top-18, label; size=9, color=name in plan.ports ? "#777777" : "#333333",
            align=angled ? (:left, :center) : (:center, :center), rotation=angled ? deg2rad(72) : 0)
        line!([point(x, top-7), point(x, bottom)]; layer=0, color="#EEEEEE", linewidth=0.35, linestyle=:dot)
    end
    for a in active
        line!([point(a.x, a.lo), point(a.x, a.hi)]; layer=0, styles.guide...)
    end
    for c in carries
        x = xs[c.name]
        offset = c.x - x
        style = styles[c.slot]
        for (a, b) in c.segments
            line!([point(x+offset, a), point(x+offset, b)]; layer=0, style...)
        end
        for y in (top-5, bottom)
            line!([point(x+offset-2, y-2), point(x+offset+2, y+2)]; layer=0, color=style.color, linewidth=style.linewidth)
        end
        line!([point(x+offset, ys[c.to]), point(x, ys[c.to])]; style...)
        line!([point(x, ys[c.from]), point(x+offset, ys[c.from])]; style...)
        arrow!(x+sign(offset)*5, ys[c.to], -sign(offset), style)
    end
    for (i, event) in enumerate(plan.events)
        x, y = xs[string(event.node.info.name)], ys[i]
        text!(20, y, string(event.order); size=8, color="#888888")
        text!(code, y-4, notes[i]; size=9, align=(:left, :top))
        groups = readgroups[i]
        for (j, (side, conditional)) in enumerate(groups)
            sources = unique(xs[r.name] for r in event.reads if (sign(xs[r.name]-x), r.role == :when) == (side, conditional))
            style = conditional ? styles.condition : styles.read
            if side == 0
                commands = [Makie.MoveTo(point(x, y-4)),
                    Makie.CurveTo(point(x-18, y-18), point(x-20, y), point(x-10, y)), Makie.LineTo(point(x-5, y))]
                path!(commands; style...)
                arrow!(x-5, y, 1, style)
                continue
            end
            direction = -side
            bus = y - (length(groups) > 1 || length(sources) > 1 ? 7 + 4(j-1) : 0)
            joins = sources .+ 8direction
            start = side < 0 ? minimum(joins) : maximum(joins)
            finish = x - 18direction
            obstacles = sort(unique(a.x for a in rails if min(start, finish)+4 < a.x < max(start, finish)-4 &&
                a.lo <= bus <= a.hi && all(abs(a.x-z) > 6 for z in joins)); rev=direction < 0)
            commands = Makie.PathCommand[Makie.MoveTo(point(start, bus))]
            for obstacle in obstacles
                push!(commands, Makie.LineTo(point(obstacle-3direction, bus)),
                    Makie.CurveTo(point(obstacle-3direction, bus-5), point(obstacle+3direction, bus-5), point(obstacle+3direction, bus)))
            end
            push!(commands, Makie.LineTo(point(finish, bus)),
                Makie.CurveTo(point(x-14direction, bus), point(x-14direction, y), point(x-10direction, y)),
                Makie.LineTo(point(x-5direction, y)))
            path!(commands; layer=1, color=:white, linewidth=2.6)
            path!(commands; style...)
            arrow!(x-5direction, y, direction, style)
            for (source, join) in zip(sources, joins)
                branch = [Makie.MoveTo(point(source+2direction, y)),
                    Makie.CurveTo(point(source+5direction, y), point(source+5direction, bus), point(join, bus))]
                path!(branch; layer=1, color=:white, linewidth=2.6)
                path!(branch; style...)
                length(sources) > 1 && dot!(join, bus; size=2, color=style.color)
            end
        end
        for r in event.reads
            dot!(xs[r.name], y; marker=r.name in plan.ports ? :rect : :circle)
        end
        operation = event.operation
        marker = operation == :state ? :rect : operation == :call ? rounded :
            operation in (:rate, :guard) ? :diamond : operation == :input ? input :
            operation == :opaque ? :hexagon : :circle
        if operation == :produce
            dot!(x, y; layer=1, marker=rounded, size=12)
            dot!(x, y; layer=2, marker=rounded, size=8)
        else
            dot!(x, y; layer=1, marker, size=operation in (:value, :memory) ? 5 : 9,
                color=operation == :value ? "#555555" : :white)
        end
    end
    isempty(plan.events) && text!(code, top+6, "No update operations in this selection."; size=9)
    labels = (:read => "read", :condition => "condition", :value => "retained value",
        :rate => "cached rate", :guide => "variable guide")
    widths = [32 + 4.8textwidth(label) for (_, label) in labels]
    for (i, (role, label)) in enumerate(labels)
        x = 20 + sum(widths[1:i-1])
        line!([point(x, bottom+20), point(x+16, bottom+20)]; styles[role]...)
        text!(x+22, bottom+20, label; size=8, color="#777777")
    end
    text!(20, bottom+33, "cut rails continue across updates; initialization and context stages are not expanded"; size=8, color="#777777")
    for ((layer, color, linewidth, linestyle), commands) in sort(collect(paths); by=p -> first(p)[1])
        Makie.lines!(scene, Makie.BezierPath(commands); color, linewidth=linewidth*scale, linestyle)
    end
    for ((layer, marker), values) in sort(collect(dots); by=p -> first(p)[1])
        Makie.scatter!(scene, Makie.Point2f[v[1] for v in values]; marker,
            markersize=[v[2] for v in values], color=[v[3] for v in values],
            strokecolor="#555555", strokewidth=0.65scale)
    end
    for ((size, color, align, rotation, T), values) in texts
        Makie.text!(scene, Makie.Point2f[v[1] for v in values]; text=T[v[2] for v in values],
            font, fontsize=size*scale, color, align, rotation)
    end
    Plot(figure)
end
