flowphase(n::VarNode) = begin
    n.step isa PreStep && return :pre
    n.step isa PostStep && return :post
    :main
end

flowlabel(n) = join(map(split(string(n), '.')) do s
    cs, cn = splitcanonicalname(Symbol(s))
    isnothing(cs) ? string(cn) : "$cs.$cn"
end, '.')
flowexpr(x) = begin
    isexpr(x, :kw) && return "$(flowexpr(first(x.args))) = $(flowexpr(last(x.args)))"
    ex = MacroTools.postwalk(x isa Expr ? Base.remove_linenums!(deepcopy(x)) : x) do a
        a isa Symbol || return a
        cs, cn = splitcanonicalname(a)
        isnothing(cs) ? a : Expr(:., cs, QuoteNode(cn))
    end
    xs = isexpr(ex, :block) ? ex.args : [ex]
    s = join((strip(sprint(Base.show_unquoted, a)) for a in xs), "; ")
    length(xs) > 1 ? "($s)" : s
end
flowdefaults(v::VarInfo) = begin
    tags = Dict{Symbol,Any}(:_type => gettag(v, :_type), :unit => gettag(v, :unit))
    updatetags!(tags, Val(v.state); kwargs = v.kwargs)
    tags
end

"""
Describe an update phase without evaluating model expressions. State adapters
mirror `genupdate`: `equation` reads declaration arguments, `tags` lists other
direct reads, and `slots` identifies values carried to the next update.
An absent action leaves the expression unlabelled; an empty action names
only the state. Shared explanations appear once in the legend.
Keep these adapters in sync with state generators; unknown states are rejected
rather than assigned guessed semantics.
"""
flowrule(operation, action = nothing; equation = false, tags = (), slots = (), hints = ()) = (; operation, action, equation, tags, slots, hints)
flowrule(::Val, v, phase) = throw(ArgumentError("no computation flow description for $(v.state)"))
flowrule(::Union{Val{:Preserve},Val{:Provide},Val{:Interpolate},Val{:Tabulate},Val{:Hold}}, v, phase) = nothing
flowrule(::Val{:Call}, v, phase) = phase == :main ? flowrule(:binding, "bound inputs"; tags = (:unit,)) : nothing
flowrule(::Union{Val{nothing},Val{:Bring}}, v, phase) = begin
    phase == :main || return nothing
    istag(v, :override, :skip) && return nothing
    flowrule(:call, "update field")
end
flowrule(::Val{:Track}, v, phase) = begin
    istag(v, :override, :skip) && return nothing
    when = hastag(v, :when)
    alt = hastag(v, :init) ? "init" : "zero"
    flowrule(:value; equation = true, tags = (:when, :unit, :min, :max, :round, (when ? (:init,) : ())...),
        hints = when ? ("track: use $alt when the condition is false",) : ())
end
flowrule(::Val{:Flag}, v, phase) = begin
    istag(v, :override, :parameter) && return nothing
    once = istag(v, :once)
    hs = if once
        ("once: a true flag stays true",)
    elseif hastag(v, :when)
        ("flag: clear when the condition is false",)
    else
        ()
    end
    flowrule(:guard; equation = true, tags = (:when,), slots = once ? (:value,) : (), hints = hs)
end
flowrule(::Val{:Remember}, v, phase) = flowrule(:memory, ""; equation = true, tags = (:when, :unit), slots = (:value,), hints = ("remember: keep the first eligible value",))
flowratehint(v) = hastag(v, :when) ? ("save rate: zero when the condition is false",) : ()
flowrule(::Val{:Accumulate}, v, phase) = begin
    reset = gettag(v, :reset) !== false
    if phase == :post
        flowrule(:rate, "save rate"; equation = true, tags = (:when, :reset), slots = (:rate,), hints = flowratehint(v))
    else
        flowrule(:state, ""; tags = (:time, :unit, :min, :max, (reset ? (:init,) : ())...), slots = (:value,),
            hints = ("accumulate: add previous rate × elapsed time",
                (reset ? ("reset: sampled with rate; if true, use init next update",) : ())...))
    end
end
flowrule(::Val{:Capture}, v, phase) = begin
    if phase == :post
        flowrule(:rate, "save rate & time"; equation = true, tags = (:when, :time), slots = (:rate,), hints = flowratehint(v))
    else
        flowrule(:state, ""; tags = (:time,), hints = ("capture: replace with previous rate × elapsed time",))
    end
end
flowrule(::Val{:Advance}, v, phase) = flowrule(:state, ""; slots = (:value,), hints = ("advance: read counter, then add stored step",))
flowrule(::Val{:Drive}, v, phase) = flowrule(:input, "read input"; tags = (:tick,))
flowrule(::Val{:Produce}, v, phase) = begin
    phase == :pre && return nothing
    single = istag(v, :single)
    child = single ? "child" : "children"
    phase == :main && return flowrule(:produce, "update $child")
    hint = single ? "queue child: only if empty; construct next update" : "queue children: construct next update"
    flowrule(:produce, "queue $child"; equation = true, tags = (:when,), hints = (hint,))
end
flowrule(::Val{:Bisect}, v, phase) = begin
    if phase == :pre
        all(k -> isnothing(gettag(v, k)), (:min, :max)) && return nothing
        return flowrule(:opaque, "clamp trial"; tags = (:min, :max))
    end
    flowrule(:opaque, ""; equation = true, tags = (:lower, :upper, :unit, :min, :max, :maxiter, :tol))
end
flowrule(::Val{:Solve}, v, phase) = flowrule(:opaque, "select root"; equation = true, tags = (:unit, :lower, :upper))
flowrule(::Val{:Integrate}, v, phase) = flowrule(:opaque, ""; equation = true, tags = (:from, :to))
flowrule(::Val{:Wrap}, v, phase) = flowrule(:opaque; equation = true)

"""Collect possible reads: `rows[i[]].x` reads `rows.x` and `i`; `f(i[]).x` and `f.(i[])` read `f` and `i`."""
flowreferences(x, tail = "") = String[]
flowreferences(x::Symbol, tail = "") = [string(x, tail)]
flowreferences(ex::Expr, tail = "") = begin
    a = ex.args
    if isexpr(ex, :(=), :kw)
        flowreferences(last(a), tail)
    elseif Meta.isexpr(ex, :., 2) && last(a) isa QuoteNode
        flowreferences(first(a), ".$(last(a).value)$tail")
    elseif isexpr(ex, Symbol("'"))
        flowreferences(first(a), tail)
    elseif isexpr(ex, :ref)
        vcat(flowreferences(first(a), tail), (flowreferences(x) for x in Iterators.drop(a, 1))...)
    elseif isexpr(ex, :comparison)
        String[p for i in 1:2:length(a) for p in flowreferences(a[i])]
    elseif isexpr(ex, :if)
        vcat(flowreferences(first(a)), (flowreferences(MacroTools.unblock(x), tail) for x in Iterators.drop(a, 1))...)
    elseif isexpr(ex, :call, :., :tuple, :parameters, :..., :&&, :||)
        String[p for x in a for p in flowreferences(x)]
    else
        String[]
    end
end

flowreads(d::Dependency, v::VarInfo; equation = true, tags = ()) = begin
    xs = vcat([(:data, a) for a in v.args if equation], [(k, gettag(v, k)) for k in tags])
    resolve(p, role) = begin
        k = Symbol(first(eachsplit(p, '.')))
        src = get(d.M, k, nothing)
        (isnothing(src) || k in (:context, :config) || istag(src, :context)) && return nothing
        name = replace(p, r"^[^.]+" => string(src.name))
        (; name, role)
    end
    reads = [resolve(p, role) for (role, x) in xs for p in flowreferences(x)]
    unique(filter(!isnothing, reads))
end

flowcode(v::VarInfo, r, scope) = begin
    ex = isnothing(v.body) && length(v.args) == 1 ? last(extractfuncargpair(only(v.args))) : v.body
    body = r.equation && !isnothing(ex) ? [flowexpr(ex)] : String[]
    args = [flowexpr(a) for a in v.args if r.equation && !isnothing(v.body) && isexpr(a, :(=), :kw) && first(a.args) != last(a.args)]
    d = flowdefaults(v)
    ks = [k for k in (r.tags..., :once, :pick) if k != :unit && hastag(v, k) &&
        !(k == :once && !istag(v, k)) &&
        (!haskey(d, k) || !isequal(gettag(v, k), d[k]))]
    ts = isempty(ks) ? () : something(last(parseline(v.line, scope)), ())
    tagkey(t) = isexpr(t, :(=), :kw) ? first(t.args) : t
    tags = [(tagkey(t), flowexpr(t)) for t in ts if tagkey(t) in ks]
    badges = (:when, :once, :reset)
    code = join([body; args; [s for (k, s) in tags if k ∉ badges]], "; ")
    state = isnothing(v.state) ? "" : lowercase(string(v.state))
    note = isnothing(r.action) ? "" : join(filter(!isempty, (state, r.action)), " · ")
    (; code, note, badges = [s for (k, s) in tags if k in badges])
end

flowplan(S::Type{<:System}, d::Dependency; selected = d) = begin
    ns = Set(n.info.name for n in selected.N)
    included(v) = v.name in ns && v.name ∉ (:context, :config) && !istag(v, :context)
    steps = sort(d)
    calls = Dict(string(n.info.name) => i for (i, n) in enumerate(steps) if n.info.state == :Call && n.step isa MainStep)
    rows = Dict{Int,NamedTuple}()
    function visit(i)
        haskey(rows, i) && return
        n = steps[i]
        v = n.info
        r = flowrule(Val(v.state), v, flowphase(n))
        isnothing(r) && return
        # A call row locates the callable; its bound inputs are read only on invocation.
        reads = flowreads(d, v; equation = r.equation || r.operation == :binding, tags = r.tags)
        r.operation == :binding && isempty(reads) && return
        prev = r.operation in (:value, :guard) && any(a -> a.name == string(v.name), reads)
        slots = prev && isempty(r.slots) ? (:value,) : r.slots
        rows[i] = (; node = n, order = i, operation = r.operation, slots, reads, flowcode(v, r, scopeof(S))..., hints = r.hints)
        foreach(a -> haskey(calls, a.name) && visit(calls[a.name]), reads)
    end
    foreach(visit, findall(n -> included(n.info), steps))
    events = [rows[i] for i in eachindex(steps) if haskey(rows, i)]
    names = [string(v.name) for v in geninfos(S) if included(v)]
    ports = sort(setdiff(String[r.name for e in events for r in e.reads], names))
    lanes = [names; ports]
    idx = Dict(e.node.info.name => i for (i, e) in enumerate(events) if flowphase(e.node) == :main)
    carries = [(; name = string(e.node.info.name), slot, from = i, to = idx[e.node.info.name]) for (i, e) in enumerate(events) if haskey(idx, e.node.info.name) for slot in e.slots]
    labels = Dict(n => flowlabel(n) for n in lanes)
    hints = unique(String[h for e in events for h in e.hints])
    (; model = string(namefor(S)), lanes, labels, ports, events, carries, hints)
end

flowwrap(text; width = 72, sep = " ") = begin
    occursin('\n', text) && return join((flowwrap(line; width, sep) for line in split(text, '\n')), '\n')
    lines = [""]
    for (i, word) in enumerate(split(text, sep; keepempty = true))
        if !isempty(last(lines)) && textwidth(last(lines)) + textwidth(word) + textwidth(sep) > width
            push!(lines, word)
        else
            lines[end] *= (i == 1 ? "" : sep) * word
        end
    end
    join(lines, '\n')
end
flowlines(s) = isempty(s) ? 0 : count(==('\n'), s) + 1
flowfont(italic = false) = Makie.assetpath("fonts", italic ? "TeXGyreHerosMakie-Italic.otf" : "DejaVuSansMono.ttf")

flowrow(e, mono, italic) = begin
    parts = Tuple{Symbol,String,Float64,Int}[]
    x, y, width, height = 0.0, 0, 0.0, 0
    for (kind, s) in [(:code, e.code); (:note, e.note); [(:badge, b) for b in e.badges]]
        isempty(s) && continue
        label = flowwrap(s)
        n = flowlines(label)
        pad = kind == :badge ? 4 : 0
        face = kind == :note ? italic : mono
        w = maximum(l -> Makie.widths(Makie.text_bb(l, face, kind == :badge ? 8.5f0 : 9f0))[1], split(label, '\n')) + 2pad
        if x > 0 && (x + w > 400 || n > 1)
            x, y = 0.0, height
        end
        push!(parts, (kind, label, x+pad, y))
        width, height = max(width, x+w), max(height, y+14n)
        x, y = n > 1 ? (0.0, height) : (x+w+8, y)
    end
    (; parts, width, height)
end

const FLOW_RAIL_TAPER = 13
const FLOW_STYLES = let read = (color = "#2D73A1", linewidth = 0.8, linestyle = :solid)
    (;
        read, binding = (; read..., linestyle = :dash),
        control = (color = "#B27A24", linewidth = 0.9, linestyle = :dot),
        value = (color = "#89949C", linewidth = 0.65, linestyle = :solid),
        rate = (color = "#258D80", linewidth = 0.75, linestyle = :solid),
        guide = (color = "#DEDEDE", linewidth = 0.4, linestyle = :solid),
    )
end

flowreadkind(e, r) = begin
    e.operation == :binding && return :binding
    r.role in (:when, :reset) ? :control : :read
end

flowlayout(plan) = begin
    mono, italic = Makie.to_font.((flowfont(), flowfont(true)))
    entries = plan.events
    rows = [flowrow(e, mono, italic) for e in entries]
    angled = any(n -> textwidth(n) > 7, values(plan.labels))
    spacing = angled ? 34 : 52
    header = angled ? max(60, maximum(textwidth.(values(plan.labels)); init = 0) * 5.8 + 16) : 34
    top = 48 + header
    rail = 18
    slots = Set((c.name, c.slot) for c in plan.carries)
    loops = Set(string(e.node.info.name) for e in entries if any(r -> r.name == string(e.node.info.name), e.reads))
    gutter(n, slot) = (n, slot) in slots ? rail : 0
    left(n) = n in loops ? rail : gutter(n, :rate)
    nd = ndigits(maximum((e.order for e in plan.events); init = 1))
    gaps = map(enumerate(plan.lanes)) do (i, n)
        if i == 1
            max(52, 27 + 5nd + left(n))
        else
            max(spacing, gutter(plan.lanes[i-1], :value) + 8 + left(n))
        end
    end
    xs = Dict(zip(plan.lanes, cumsum(gaps)))
    readgroups = [unique((sign(xs[r.name]-xs[string(e.node.info.name)]), flowreadkind(e, r)) for r in e.reads) for e in entries]
    entry = any(c -> c.to == 1, plan.carries) ? 16 + FLOW_RAIL_TAPER : 0
    above = Int[max(i == 1 ? entry : 0, 18 + 4max(0, length(g)-1)) for (i, g) in enumerate(readgroups)]
    below = [max(16, r.height-2) for r in rows]
    bounds = top .+ [0; cumsum(above .+ below)]
    ys = bounds[2:end] .- below
    bottom = last(bounds) + 18
    target = maximum(values(xs); init = 52-spacing) + spacing + 28
    nw = maximum((textwidth(plan.labels[string(e.node.info.name)]) for e in entries); init = 0)
    content = target + 6nw + 12
    width = content + maximum((r.width for r in rows); init = 350) + 24
    sep = "   ·   "
    key = flowwrap(join(plan.hints, sep); width = floor(Int, (width-40)/4.85), sep)
    hinty = bottom + (isempty(plan.carries) ? 30 : 42)
    height = (isempty(rows) ? bottom+6 : hinty) + 3 + 12flowlines(key)
    uses(e, n) = string(e.node.info.name) == n || any(r -> r.name == n, e.reads)
    lastuse(n) = maximum((ys[i] for (i, e) in enumerate(entries) if uses(e, n)); init = top-6)
    active = [(x = xs[n], lo = top-6, hi = lastuse(n)) for n in plan.lanes]
    carries = [(; c..., x = xs[c.name] + (c.slot == :rate ? -rail : rail),
        segments = ((top-5, ys[c.to]-16), (ys[c.from]+16, bottom))) for c in plan.carries]
    (; rows, angled, top, xs, ys, bounds, bottom, target, content, width, height, readgroups, active, carries, hinty, key)
end

struct FlowDiagram{P,F<:Real}
    plan::P
    fontsize::F
end
include("flowtext.jl")
Base.show(io::IO, r::FlowDiagram) = print(io, "Computation flow for $(r.plan.model) ($(length(r.plan.events)) operations)")
Base.showable(m::MIME, ::FlowDiagram) = Makie.backend_showable(CairoMakie.Screen, m)
Base.showable(::MIME"text/plain", ::FlowDiagram) = true
Base.show(io::IO, m::MIME, r::FlowDiagram) = show(io, m, flowdraw(r)[]; backend = CairoMakie)
writeimage(name::AbstractString, r::FlowDiagram; kw...) = writeimage(name, flowdraw(r); kw...)

flowdiagram(S::Type{<:System}, d::Dependency; selected = d, style = ()) = begin
    opt = (; style...)
    all(k -> k == :fontsize, keys(opt)) || throw(ArgumentError("flow style supports only fontsize"))
    fs = get(opt, :fontsize, 10)
    fs isa Real && isfinite(fs) && fs > 0 || throw(ArgumentError("fontsize must be a positive finite number"))
    FlowDiagram(flowplan(S, d; selected), fs)
end

flowdraw(r::FlowDiagram) = flowdraw(r.plan, flowlayout(r.plan), r.fontsize)
flowdraw(plan, layout, fontsize) = begin
    (; rows, angled, top, xs, ys, bounds, bottom, target, content, width, height, readgroups, active, carries, hinty, key) = layout
    styles = FLOW_STYLES
    scale = fontsize / 10
    fig = Makie.with_theme(theme_classic()) do
        Makie.Figure(size = ceil.(Int, (width, height) .* scale), figure_padding = 0, backgroundcolor = :white)
    end
    scene = fig.scene
    Makie.campixel!(scene)
    point(x, y) = Makie.Point2f(x * scale, (height - y) * scale)
    bend(x, y1, y2, d, slope = 0) = Makie.CurveTo(point(x+5d, y1), point(x+5d, y2+5slope), point(x+10d, y2))
    font = flowfont()
    texts, paths, dots = Dict(), Dict(), Dict()
    badges = Tuple{Makie.Point2f,String}[]
    text!(x, y, text; size = 10, color = "#333333", align = (:left, :center), rotation = 0, face = font) = push!(get!(texts, (size, color, align, rotation, face, typeof(text)), []), (point(x, y), text))
    path!(cmds; layer = 2, color = styles.read.color, linewidth = styles.read.linewidth, linestyle = :solid) = append!(get!(paths, (layer, color, linewidth, linestyle), Makie.PathCommand[]), cmds)
    line!(points; kw...) = path!([Makie.MoveTo(first(points)); Makie.LineTo.(points[2:end])]; kw...)
    dot!(x, y; layer = 0, marker = :circle, size = 4, color = :white, stroke = 0.65) = push!(get!(dots, (layer, marker, stroke), []), (point(x, y), size*scale, Makie.to_color(color)))
    rail!(x, y, dx, dy, span, style) = begin
        at(d) = point(x+d*dx, y+d*dy)
        for (a, b) in ((3, 5), (7, 11), (FLOW_RAIL_TAPER, span))
            line!([at(a), at(b)]; layer = 0, style...)
        end
        dot!(x, y; size = 1.6, color = style.color, stroke = 0)
    end
    arrow!(x, y, dx, style = styles.read; dy = 0) = begin
        ux, uy = (dx, dy) ./ hypot(dx, dy)
        at(back, side = 0) = point(x-back*ux-side*uy, y-back*uy+side*ux)
        path!([
            Makie.MoveTo(at(5)), Makie.LineTo(at(0)),
            Makie.MoveTo(at(3.5, -1.5)), Makie.LineTo(at(0)), Makie.LineTo(at(3.5, 1.5)),
        ]; color = style.color, linewidth = style.linewidth)
    end
    input = Makie.BezierPath([
        Makie.MoveTo(-0.5, -0.3),
        Makie.LineTo(0.3, -0.3), Makie.LineTo(0.5, 0.3), Makie.LineTo(-0.3, 0.3),
        Makie.ClosePath(),
    ])
    rounded = Makie.BezierPath([
        Makie.MoveTo(-0.3, -0.5),
        Makie.LineTo(0.3, -0.5), Makie.CurveTo(0.5, -0.5, 0.5, -0.5, 0.5, -0.3),
        Makie.LineTo(0.5, 0.3), Makie.CurveTo(0.5, 0.5, 0.5, 0.5, 0.3, 0.5),
        Makie.LineTo(-0.3, 0.5), Makie.CurveTo(-0.5, 0.5, -0.5, 0.5, -0.5, 0.3),
        Makie.LineTo(-0.5, -0.3), Makie.CurveTo(-0.5, -0.5, -0.5, -0.5, -0.3, -0.5),
        Makie.ClosePath(),
    ])
    markers = (; state = :rect, call = rounded, binding = :dtriangle, rate = :utriangle, guard = :diamond, input, opaque = :hexagon)
    text!(20, 20, plan.model; size = 12)
    text!(20, 37, "one update · static order, not elapsed time"; size = 8, color = "#777777")
    heading = Makie.rich("Computation     model code  /  ", Makie.rich("Cropbox action"; font = :italic), "  /  tags")
    text!(target, top-16, heading; size = 8, color = "#666666")
    for y in bounds
        line!([point(12, y), point(width-16, y)]; layer = -1, color = "#E0E0E0", linewidth = 0.45)
    end
    for name in plan.lanes
        x = xs[name]
        label = if occursin('.', plan.labels[name])
            prefix, leaf = String.(rsplit(plan.labels[name], '.'; limit = 2))
            Makie.rich(Makie.rich(prefix; color = "#888888"), Makie.rich("."; color = "#BBBBBB"), Makie.rich(leaf; color = "#333333"))
        else
            plan.labels[name]
        end
        text!(x, top-18, label; size = 9, color = name in plan.ports ? "#777777" : "#333333", align = angled ? (:left, :center) : (:center, :center), rotation = angled ? deg2rad(72) : 0)
        line!([point(x, top-7), point(x, bottom)]; layer = 0, color = "#EEEEEE", linewidth = 0.35, linestyle = :dot)
    end
    for a in active
        line!([point(a.x, a.lo), point(a.x, a.hi)]; layer = 0, styles.guide...)
    end
    for c in carries
        x = xs[c.name]
        side = sign(c.x - x)
        style = styles[c.slot]
        upper, lower = c.segments
        for (i, v, (cap, elbow)) in ((c.to, -1, upper), (c.from, 1, reverse(lower)))
            y = ys[i]
            rail!(c.x, cap, 0, -v, abs(elbow-cap), style)
            tip = v < 0 ? 4 : 0
            tx, ty = x+tip*side, y+1.5tip*v
            path!([
                Makie.MoveTo(point(c.x, elbow)),
                Makie.CurveTo(point(c.x, y+12v), point(x+9side, y+13.5v), point(x+7side, y+10.5v)),
                Makie.LineTo(point(tx, ty)),
            ]; color = style.color, linewidth = style.linewidth)
            v < 0 && arrow!(tx, ty, -side, style; dy = 1.5)
        end
    end
    for (i, e) in enumerate(plan.events)
        n = string(e.node.info.name)
        x, y = xs[n], ys[i]
        text!(20, y, string(e.order); size = 8, color = "#888888")
        text!(target, y-4, plan.labels[n]; size = 9, align = (:left, :top))
        for (kind, label, dx, dy) in rows[i].parts
            px, py = content+dx, y-4+dy
            if kind == :badge
                push!(badges, (point(px, py), label))
            else
                note = kind == :note
                text!(px, py, label; size = 9, align = (:left, :top), color = note ? "#495057" : "#333333", face = note ? flowfont(true) : font)
            end
        end
        groups = readgroups[i]
        for (side, role) in groups
            style = styles[role]
            control = role == :control
            paired = (side, control ? :read : :control) in groups
            if side == 0
                v = paired && control ? 1 : -1
                ty = paired ? y+2v : y
                cmds = [Makie.MoveTo(point(x, y+4v)), Makie.CurveTo(point(x-18, y+18v), point(x-20, ty), point(x-10, ty)), Makie.LineTo(point(x-5, ty))]
                path!(cmds; style...)
                arrow!(x-5, ty, 1, style)
                continue
            end
            d = -side
            src = sort(unique(xs[r.name] for r in e.reads if (sign(xs[r.name]-x), flowreadkind(e, r)) == (side, role)); by = s -> abs(s-x))
            slope, dy = if paired
                control ? (-0.5, -12) : (0.5, 8)
            else
                (0.0, control ? -12 : -8)
            end
            level = length(groups) > 1 || length(src) > 1 ? y+dy : y
            gap = iszero(slope) ? 5 : 7
            landing = x-(gap+15)*d
            for (k, sx) in enumerate(src)
                x0 = sx+2d
                if k == 1
                    tip, tipy = x-gap*d, y+gap*slope
                    descent = (Makie.LineTo(point(landing, level)), bend(landing, level, y+(gap+5)*slope, d, slope))
                else
                    tip, tipy = src[k-1]+6d, level
                    descent = ()
                end
                cmds = [Makie.MoveTo(point(x0, y)), bend(x0, y, level, d), descent..., Makie.LineTo(point(tip, tipy))]
                path!(cmds; layer = 1, color = :white, linewidth = 2.6)
                path!(cmds; style...)
                arrow!(tip, tipy, d, style; dy = k == 1 ? -slope : 0)
            end
        end
        for r in e.reads
            dot!(xs[r.name], y; marker = r.name in plan.ports ? :rect : :circle)
        end
        op = e.operation
        if op == :produce
            dot!(x, y; layer = 1, marker = rounded, size = 12)
            dot!(x, y; layer = 2, marker = rounded, size = 8)
        else
            marker = get(markers, op, :circle)
            dot!(x, y; layer = 1, marker, size = op in (:value, :memory) ? 5 : 9, color = op == :value ? "#555555" : :white)
        end
    end
    isempty(plan.events) && text!(target, top+6, "No update operations in this selection."; size = 9, face = :italic)
    labels = (:read => "read", :binding => "bound input", :control => "control", :value => "value (right)", :rate => "rate (left)", :guide => "variable guide")
    used = union(Symbol[k for g in readgroups for (_, k) in g], (c.slot for c in carries))
    labels = filter(p -> first(p) in used || (first(p) == :guide && !isempty(rows)), labels)
    widths = [32 + 4.8textwidth(label) for (_, label) in labels]
    for (i, (role, label)) in enumerate(labels)
        x = 20 + sum(widths[1:i-1])
        if role in (:value, :rate)
            rail!(x+18, bottom+20, -1, 0, 18, styles[role])
        else
            line!([point(x, bottom+20), point(x+16, bottom+20)]; styles[role]...)
        end
        text!(x+22, bottom+20, label; size = 8, color = "#777777")
    end
    isempty(carries) || text!(20, bottom+33, "fading ends: read above from the previous update; save below for the next"; size = 8, color = "#777777")
    isempty(key) || text!(20, hinty, key; size = 8, color = "#666666", align = (:left, :top))
    for ((layer, color, linewidth, linestyle), cmds) in sort(collect(paths); by = p -> first(p)[1])
        Makie.lines!(scene, Makie.BezierPath(cmds); color, linewidth = linewidth*scale, linestyle)
    end
    for ((layer, marker, stroke), values) in sort(collect(dots); by = p -> first(p)[1])
        Makie.scatter!(scene, Makie.Point2f[v[1] for v in values];
            marker,
            markersize = [v[2] for v in values],
            color = [v[3] for v in values],
            strokecolor = "#555555",
            strokewidth = stroke*scale,
        )
    end
    for ((size, color, align, rotation, face, T), values) in texts
        Makie.text!(scene, Makie.Point2f[v[1] for v in values]; text = T[v[2] for v in values], font = face, fontsize = size*scale, color, align, rotation)
    end
    if !isempty(badges)
        Makie.textlabel!(scene, first.(badges);
            text = last.(badges),
            font,
            fontsize = 8.5scale,
            text_align = (:left, :top),
            padding = (4, 4, 1, 1) .* scale,
            cornerradius = 4scale,
            text_color = "#41474A",
            background_color = :white,
            strokecolor = "#B4BABD",
            strokewidth = 0.6scale,
        )
    end
    Plot(fig)
end
