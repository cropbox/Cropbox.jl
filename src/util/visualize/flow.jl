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
only the state.
Keep these adapters in sync with state generators; unknown states are rejected
rather than assigned guessed semantics.
"""
flowrule(operation, action = nothing; equation = false, tags = (), slots = ()) = (; operation, action, equation, tags, slots)
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
    flowrule(:value; equation = true, tags = (:when, :unit, :min, :max, :round, (hastag(v, :when) ? (:init,) : ())...))
end
flowrule(::Val{:Flag}, v, phase) = begin
    istag(v, :override, :parameter) && return nothing
    flowrule(:guard; equation = true, tags = (:when,), slots = istag(v, :once) ? (:value,) : ())
end
flowrule(::Val{:Remember}, v, phase) = flowrule(:memory, ""; equation = true, tags = (:when, :unit), slots = (:value,))
flowrule(::Val{:Accumulate}, v, phase) = begin
    reset = gettag(v, :reset) !== false
    if phase == :post
        flowrule(:rate, "save rate"; equation = true, tags = (:when, :reset), slots = (:rate,))
    else
        flowrule(:state, ""; tags = (:time, :unit, :min, :max, (reset ? (:init,) : ())...), slots = (:value,))
    end
end
flowrule(::Val{:Capture}, v, phase) = begin
    if phase == :post
        flowrule(:rate, "save rate & time"; equation = true, tags = (:when, :time), slots = (:rate,))
    else
        flowrule(:state, ""; tags = (:time,))
    end
end
flowrule(::Val{:Advance}, v, phase) = flowrule(:state, ""; slots = (:value,))
flowrule(::Val{:Drive}, v, phase) = flowrule(:input, "read input"; tags = (:tick,))
flowrule(::Val{:Produce}, v, phase) = begin
    phase == :pre && return nothing
    child = istag(v, :single) ? "child" : "children"
    phase == :main && return flowrule(:produce, "update $child")
    flowrule(:produce, "queue $child"; equation = true, tags = (:when,))
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
    behavior = isnothing(r.action) || isnothing(v.state) ? "" : lowercase(string(v.state))
    (; code, behavior, note = something(r.action, ""), badges = [s for (k, s) in tags if k in badges])
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
        rows[i] = (; node = n, order = i, operation = r.operation, slots, reads, flowcode(v, r, scopeof(S))...)
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
    (; model = string(namefor(S)), lanes, labels, ports, events, carries)
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
flowfont(italic = false) = Makie.assetpath("fonts", italic ? "TeXGyreHerosMakie-Italic.otf" : "DejaVuSansMono.ttf")
flowbold() = Makie.assetpath("fonts", "NotoSans-Bold.ttf")
flowwidth(s, face, size) = Makie.widths(Makie.text_bb(s, face, Float32(size)))[1]
flowleading(size) = ceil(Int, 1.4size)
const FLOW_EMPTY = "No update operations in this selection."

flowtoken(k) = begin
    k in (:julia_operator, :julia_comparator, :julia_assignment, :julia_opassignment, :julia_typedec, :julia_broadcast, :julia_builtin) && return "#395F8A"
    k in (:julia_number, :julia_bool, :julia_singleton_identifier) && return "#924B20"
    k == :julia_keyword && return "#765283"
    k in (:julia_string, :julia_string_delim, :julia_char, :julia_char_delim) && return "#42634D"
    (k == :julia_parentheses || startswith(String(k), "julia_rainbow_")) && return "#636D73"
    nothing
end
flowsyntax(s) = map(split(JuliaSyntaxHighlighting.highlight(s), '\n'; keepempty = true)) do line
    isempty(line) && return ""
    parts = map(collect(Base.eachregion(line))) do (part, as)
        i = findlast(a -> a.label == :face && !isnothing(flowtoken(a.value)), as)
        isnothing(i) ? String(part) : Makie.rich(String(part); color = flowtoken(as[i].value))
    end
    all(p -> p isa String, parts) ? String(line) : Makie.rich(parts...)
end

flowrow(e, mono, italic, bold, fs) = begin
    parts = Tuple{Symbol,String,Float64,Int}[]
    chips = NamedTuple[]
    x, y, width, height, indent = 0.0, 0, 0.0, 0, 0.0
    for (kind, s) in [(:behavior, e.behavior); (:code, e.code); (:note, e.note); [(:badge, b) for b in e.badges]]
        isempty(s) && continue
        tag = kind == :badge ? split(s, " = "; limit = 2) : ()
        pair = length(tag) == 2
        label = flowwrap(pair ? last(tag) : s)
        lines = split(label, '\n')
        n = length(lines)
        chip = kind in (:behavior, :badge)
        pad = chip ? 4 : 0
        face = kind == :behavior ? bold : kind == :note ? italic : mono
        prefix = pair ? flowwidth(first(tag), mono, fs.small) + 2pad : 0.0
        w = prefix + maximum(l -> flowwidth(l, face, chip ? fs.small : fs.body), lines) + 2pad
        if x > indent && (x + w > 400 || n > 1)
            x, y = indent, height
        end
        if pair
            h = Makie.widths(Makie.text_bb(first(tag), mono, Float32(fs.small)))[2] + 2 + (n-1)*flowleading(fs.small)
            push!(chips, (; x, y, w, h, prefix))
            push!(parts, (:key, first(tag), x+pad, y))
        end
        push!(parts, (pair ? :qualifier : kind, label, x+prefix+pad, y))
        width, height = max(width, x+w), max(height, y+flowleading(fs.body)*n)
        kind == :behavior && (indent = x+w+8)
        x, y = n > 1 ? (indent, height) : (x+w+8, y)
    end
    (; parts, chips, width, height)
end

const FLOW_RAIL_TAPER = 13
flowradius(op) = op == :input ? 7 : 6
flowport(x, y, r, dx, dy) = (x, y) .+ (dx, dy) .* (r / hypot(dx, dy))
const FLOW_INK = (calculation = "#464B50", read = "#21669A", binding = "#803E96", control = "#83610F", value = "#536777", rate = "#006E53", system = "#994A36")
const FLOW_GROUP = (value = :calculation, opaque = :calculation, memory = :value, state = :rate, rate = :rate, input = :read, binding = :binding, guard = :control, call = :system, produce = :system)
flowink(op) = FLOW_INK[FLOW_GROUP[op]]
flowtint(ink, strength = 0.18) = let c = Makie.to_color(ink)
    Makie.RGBf(map(x -> 1 - strength*(1-x), (c.r, c.g, c.b))...)
end
const FLOW_STYLES = let c = FLOW_INK
    (;
        read = (color = c.read, linewidth = 0.8, linestyle = :solid),
        binding = (color = c.binding, linewidth = 0.85, linestyle = :dash),
        control = (color = c.control, linewidth = 0.9, linestyle = :dot),
        value = (color = c.value, linewidth = 0.6, linestyle = :solid),
        rate = (color = c.rate, linewidth = 0.75, linestyle = :solid),
        guide = (color = "#DEDEDE", linewidth = 0.4, linestyle = :solid),
    )
end

flowreadkind(e, r) = begin
    e.operation == :binding && return :binding
    r.role in (:when, :reset) ? :control : :read
end

flowlayout(plan, theme = theme_classic()) = begin
    mono, italic, bold = Makie.to_font.((flowfont(), flowfont(true), flowbold()))
    body = theme.Axis.xticklabelsize[]
    fs = (; body, small = body - 1, title = theme.Axis.titlesize[])
    entries = plan.events
    rows = [flowrow(e, mono, italic, bold, fs) for e in entries]
    widths = Dict(n => flowwidth(plan.labels[n], mono, body) for n in plan.lanes)
    step = 52
    neighbors = zip(plan.lanes, Iterators.drop(plan.lanes, 1))
    angled = any((widths[a] + widths[b])/2 + 6 > step for (a, b) in neighbors)
    spacing = angled ? 34 : step
    heading = angled ? 32 + ceil(Int, maximum(values(widths))*sind(72)) : 40
    top = heading + 16
    rail = 18
    slots = Set((c.name, c.slot) for c in plan.carries)
    loops = Set(string(e.node.info.name) for e in entries if any(r -> r.name == string(e.node.info.name), e.reads))
    gutter(n, slot) = (n, slot) in slots ? rail : 0
    left(n) = n in loops ? rail : gutter(n, :rate)
    numx = 12 + flowwidth(string(length(entries)), mono, fs.small)
    gaps = map(enumerate(plan.lanes)) do (i, n)
        if i == 1
            max(52, numx + 10 + max(left(n), angled ? 0 : widths[n]/2))
        else
            max(spacing, gutter(plan.lanes[i-1], :value) + 8 + left(n))
        end
    end
    xs = Dict(zip(plan.lanes, cumsum(gaps)))
    readgroups = [unique((sign(xs[r.name]-xs[string(e.node.info.name)]), flowreadkind(e, r)) for r in e.reads) for e in entries]
    entry = any(c -> c.to == 1, plan.carries) ? 16 + FLOW_RAIL_TAPER : 0
    above = Int[max(i == 1 ? entry : 0, 18 + 4max(0, length(g)-1)) for (i, g) in enumerate(readgroups)]
    below = [max(r.height-2, (0, :control) in g && (0, :read) in g ? 21 : 16) for (r,g) in zip(rows, readgroups)]
    bounds = top .+ [0; cumsum(above .+ below)]
    ys = bounds[2:end] .- below
    bottom = last(bounds) + (isempty(plan.carries) ? 0 : 18)
    edge = maximum((xs[n] + widths[n]*(angled ? cosd(72) : 0.5) for n in plan.lanes); init = 40)
    target = max(edge + 16, maximum(values(xs); init = 40) + 28)
    right = target + (isempty(rows) ? flowwidth(FLOW_EMPTY, italic, body) : maximum(r.width for r in rows))
    width = max(12 + flowwidth(plan.model, mono, fs.title), right) + 16
    height = bottom + (isempty(rows) ? 28 : 8)
    uses(e, n) = string(e.node.info.name) == n || any(r -> r.name == n, e.reads)
    lastuse(n) = maximum((ys[i] for (i, e) in enumerate(entries) if uses(e, n)); init = top-6)
    active = [(x = xs[n], lo = top-6, hi = lastuse(n)) for n in plan.lanes]
    carries = [(; c..., x = xs[c.name] + (c.slot == :rate ? -rail : rail),
        segments = ((top-5, ys[c.to]-16), (ys[c.from]+16, bottom))) for c in plan.carries]
    (; rows, fs, angled, heading, top, xs, ys, bounds, bottom, numx, target, width, height, readgroups, active, carries)
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
    fs = get(opt, :fontsize, 11)
    fs isa Real && isfinite(fs) && fs > 0 || throw(ArgumentError("fontsize must be a positive finite number"))
    FlowDiagram(flowplan(S, d; selected), fs)
end

flowdraw(r::FlowDiagram) = begin
    plan, theme = r.plan, theme_classic()
    (; rows, fs, angled, heading, top, xs, ys, bounds, bottom, numx, target, width, height, readgroups, active, carries) = flowlayout(plan, theme)
    styles = FLOW_STYLES
    scale = r.fontsize / 10
    fig = Makie.with_theme(theme) do
        Makie.Figure(size = ceil.(Int, (width, height) .* scale), figure_padding = 0, backgroundcolor = :white)
    end
    scene = fig.scene
    Makie.campixel!(scene)
    point(x, y) = Makie.Point2f(x * scale, (height - y) * scale)
    bend(x, y1, y2, d, slope = 0) = Makie.CurveTo(point(x+5d, y1), point(x+5d, y2+5slope), point(x+10d, y2))
    font = flowfont()
    texts, paths, dots = Dict(), Dict(), Dict()
    badges = Dict{Tuple{Symbol,String},Vector{Tuple{Makie.Point2f,String}}}()
    caps, keys = Vector{Makie.Point2f}[], Vector{Makie.Point2f}[]
    text!(x, y, text; size = fs.body, color = "#333333", align = (:left, :center), rotation = 0, face = font) = push!(get!(texts, (size, color, align, rotation, face, typeof(text)), []), (point(x, y), text))
    syntax!(x, y, s, size) = foreach(enumerate(flowsyntax(s))) do (i, line)
        line == "" || text!(x, y+(i-1)*flowleading(size), line; size, align = (:left, :top))
    end
    path!(cmds; layer = 2, color = styles.read.color, linewidth = styles.read.linewidth, linestyle = :solid) = append!(get!(paths, (layer, color, linewidth, linestyle), Makie.PathCommand[]), cmds)
    line!(points; kw...) = path!([Makie.MoveTo(first(points)); Makie.LineTo.(points[2:end])]; kw...)
    dot!(x, y; layer = 0, marker = :circle, size = 4, color = :white, ink = "#555555", stroke = 0.65) = push!(get!(dots, (layer, marker, stroke), []), (point(x, y), size*scale, Makie.to_color(color), Makie.to_color(ink)))
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
    text!(12, 16, plan.model; size = fs.title)
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
        text!(x, heading, label; color = name in plan.ports ? "#777777" : "#333333", align = angled ? (:left, :center) : (:center, :center), rotation = angled ? deg2rad(72) : 0)
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
            tx, ty = flowport(x, y, flowradius(plan.events[i].operation), side, 1.5v)
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
        text!(numx, y, string(i); size = fs.small, color = "#777777", align = (:right, :center))
        op = e.operation
        ink = flowink(op)
        rad = flowradius(op)
        for c in rows[i].chips
            px, py = target+c.x, y-4+c.y
            box = Makie.Rect2f(point(px, py+c.h-1), Makie.Vec2f(c.w, c.h)*scale)
            rim = Makie.Point2f.(Makie.roundedrectvertices(box, 4scale, 8))
            push!(caps, rim)
            # Keep the outer capsule continuous under the straight two-tone seam.
            seam = (px+c.prefix)*scale
            push!(keys, [Makie.Point2f(min(p[1], seam), p[2]) for p in rim])
        end
        for (kind, label, dx, dy) in rows[i].parts
            px, py = target+dx, y-4+dy
            if kind in (:behavior, :badge)
                key = (kind, kind == :behavior ? ink : "#63686E")
                push!(get!(() -> Tuple{Makie.Point2f,String}[], badges, key), (point(px, py), label))
            elseif kind == :key
                text!(px, py, label; size = fs.small, align = (:left, :top), color = "#FAFAFA")
            elseif kind == :note
                text!(px, py, label; align = (:left, :top), color = "#495057", face = flowfont(true))
            else
                syntax!(px, py, label, kind == :qualifier ? fs.small : fs.body)
            end
        end
        groups = readgroups[i]
        for (side, role) in groups
            style = styles[role]
            control = role == :control
            paired = (side, control ? :read : :control) in groups
            if side == 0
                v = paired && control ? 1 : -1
                slope = paired ? sqrt(3) : 1
                sx, sy = flowport(x, y, rad, 0, v)
                tx, ty = flowport(x, y, rad, -1, slope*v)
                cmds = [
                    Makie.MoveTo(point(sx, sy)),
                    Makie.CurveTo(point(sx, sy+14v), point(x-13, sy+14v), point(x-13, sy+5v)),
                    Makie.CurveTo(point(x-13, sy+2v), point(tx-4, ty+4slope*v), point(tx, ty)),
                ]
                path!(cmds; style...)
                arrow!(tx, ty, 1, style; dy = -slope*v)
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
            tx, ty = flowport(x, y, rad, -d, slope)
            landing = tx-15d
            for (k, sx) in enumerate(src)
                x0 = sx+2d
                if k == 1
                    tip, tipy = tx, ty
                    descent = (Makie.LineTo(point(landing, level)), bend(landing, level, ty+5slope, d, slope))
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
        for a in e.reads
            a.name == n || dot!(xs[a.name], y; marker = a.name in plan.ports ? :rect : :circle)
        end
        if op in (:call, :produce)
            dot!(x, y; layer = 1, marker = rounded, size = 6.5, ink)
            op == :produce && dot!(x, y; layer = 2, marker = rounded, size = 3.15, ink)
        else
            marker = get(markers, op, :circle)
            size = op in (:value, :memory) ? 5 : op in (:rate, :binding) ? 8 : op == :state ? 8.5 : 9
            dot!(x, y; layer = 1, marker, size, color = op == :value ? ink : :white, ink)
        end
    end
    isempty(rows) && text!(target, top+6, FLOW_EMPTY; align = (:left, :top), face = flowfont(true))
    for ((layer, color, linewidth, linestyle), cmds) in sort(collect(paths); by = p -> first(p)[1])
        Makie.lines!(scene, Makie.BezierPath(cmds); color, linewidth = linewidth*scale, linestyle)
    end
    if !isempty(rows)
        ps = Makie.Point2f[point(xs[string(e.node.info.name)], y) for (e, y) in zip(plan.events, ys)]
        disk = Makie.BezierPath([Makie.MoveTo(1, 0), Makie.EllipticalArc(Makie.Point2d(0), 1, 1, 0, 0, 2pi), Makie.ClosePath()])
        Makie.scatter!(scene, ps; marker = disk, markersize = [flowradius(e.operation)*scale for e in plan.events],
            color = [flowtint(flowink(e.operation)) for e in plan.events], strokewidth = 0)
    end
    for ((layer, marker, stroke), values) in sort(collect(dots); by = p -> first(p)[1])
        Makie.scatter!(scene, Makie.Point2f[v[1] for v in values];
            marker,
            markersize = [v[2] for v in values],
            color = [v[3] for v in values],
            strokecolor = [v[4] for v in values],
            strokewidth = stroke*scale,
        )
    end
    if !isempty(caps)
        Makie.poly!(scene, caps; color = "#EEF0F1", strokewidth = 0)
        Makie.poly!(scene, keys; color = "#63686E", strokewidth = 0)
    end
    for ((size, color, align, rotation, face, T), values) in texts
        Makie.text!(scene, Makie.Point2f[v[1] for v in values]; text = T[v[2] for v in values], font = face, fontsize = size*scale, color, align, rotation)
    end
    for ((kind, ink), bs) in badges
        behavior = kind == :behavior
        Makie.textlabel!(scene, first.(bs);
            text = last.(bs),
            font = behavior ? flowbold() : font,
            fontsize = fs.small*scale,
            text_align = (:left, :top),
            padding = (4, 4, 1, 1) .* scale,
            cornerradius = (behavior ? 2.5 : 4)*scale,
            text_color = behavior ? ink : "#FAFAFA",
            background_color = behavior ? flowtint(ink) : ink,
            strokewidth = 0,
        )
    end
    Plot(fig)
end
