flowtextrows(p) = begin
    links = [(prev = String[], next = String[]) for _ in p.events]
    for c in p.carries
        i, j = c.from, c.to
        if i == j
            push!(links[j].prev, p.labels[c.name])
        else
            push!(links[j].prev, "#$i")
            push!(links[i].next, "#$j")
        end
    end
    map(enumerate(p.events)) do (i, e)
        key = string(e.node.info.name)
        mark = get((rate = "△", binding = "▽"), e.operation, (pre = "◓", main = "○", post = "◒")[flowphase(e.node)])
        inputs = unique(r.name for r in e.reads if flowreadkind(e, r) != :control)
        tags = ["[" * replace(b, " = " => " "; count = 1) * "]" for b in e.badges]
        (; key, target = p.labels[key], mark, inputs, links[i]..., tags, e.operation, num = string(i))
    end
end

flowtextlink(xs, arrow, step) = begin
    isempty(xs) && return ()
    s = length(xs) == 1 ? only(xs) : "(" * join(xs, ", ") * ")"
    (("$arrow $s", :light_black, "  "), ("[$step update]", :cyan, " "))
end

# The strokes form one bus into this target; only marked lanes are inputs.
flowtextbus(put, src, x, e) = begin
    lo, hi = extrema([x; src])
    cs = fill(' ', hi)
    cs[lo:hi] .= e.operation == :binding ? '╌' : '─'
    cs[src] .= '●'
    lo < x && (cs[x-1] = '→')
    x < hi && (cs[x+1] = '←')
    put(String(cs[1:x-1]), :light_blue)
    self = x in src
    put(self && e.mark == "○" ? "↺" : e.mark, e.operation == :rate ? :cyan : :normal)
    put(String(cs[x+1:end]), :light_blue)
    self && e.mark != "○" && put(" ↺", :light_blue)
end

flowtextlist(put, line, src, arrow, inset, cols) = begin
    s = join(src, ", ")
    w = textwidth(arrow)
    lead = isempty(arrow) ? "" : "$arrow "
    gs = textwidth(s)+textwidth(lead) <= cols-inset ? (s,) : split(flowwrap(s; width = cols-inset-w-3, sep = ", "), '\n')
    top = length(gs) == 1 ? lead : arrow * "┬─ "
    for (j, g) in enumerate(gs)
        j == 1 || line(inset)
        put(j == 1 ? top : " "^w * (j == length(gs) ? "└─ " : "├─ "), :light_blue)
        put(g)
    end
end

Base.show(io::IO, ::MIME"text/plain", r::FlowDiagram) = begin
    p = r.plan
    rows = flowtextrows(p)
    cols = max(1, displaysize(io)[2])
    if isempty(rows)
        msg = "No update operations."
        return print(io, textwidth(msg) <= cols ? msg : "∅")
    end
    nw = maximum(e -> textwidth(e.num), rows)
    left = nw + maximum(e -> textwidth(e.target), rows) + 5
    used = Set(n for e in rows for n in (e.key, e.inputs...))
    lanes = filter(in(used), p.lanes)
    labels = [p.labels[n] for n in lanes]
    gap = "    "
    grid = left + textwidth(join(labels, gap)) <= cols
    xs = Dict{String,Int}()

    col = -1
    line(n = 0) = begin
        col >= 0 && print(io, '\n')
        print(io, " "^n)
        col = n
    end
    ink(s, color) = color == :normal ? print(io, s) : printstyled(io, s; color)
    function put(s, color = :normal)
        w = textwidth(s)
        if col + w <= cols && !occursin('\n', s)
            ink(s, color)
            col += w
        else
            # Only an individual overlong name or tag needs to break inside the text.
            for ch in Base.Unicode.graphemes(s)
                if ch == "\n"
                    line()
                    continue
                end
                w = textwidth(ch)
                col > 0 && col+w > cols && line()
                ink(ch, color)
                col += w
            end
        end
    end
    if grid
        line(left)
        for (i, (n, s)) in enumerate(zip(lanes, labels))
            i > 1 && put(gap)
            xs[n] = col-left+1 + (textwidth(s)-1)÷2
            put(s)
        end
    end
    for e in rows
        line()
        put(lpad(e.num, nw), :light_black)
        put(" ")
        if !grid
            put(e.mark in ("◓", "◒") ? e.mark : " ")
        end
        put(" " * e.target)
        src = [p.labels[k] for k in e.inputs if grid || k != e.key || e.target ∉ e.prev]
        notes = (flowtextlink(e.prev, "←", "prev")..., ((s, :yellow, "  ") for s in e.tags)..., flowtextlink(e.next, "→", "next")...)
        !grid && isempty(src) && isempty(notes) && continue
        longest = max(maximum(textwidth, src; init = 0) + 4, maximum(x -> textwidth(first(x)), notes; init = 0))
        inset = left
        if !grid && inset+longest > cols
            inset = clamp(cols-longest, 0, nw+2)
            line(inset)
        else
            put(" "^(left-col))
        end
        if grid
            flowtextbus(put, [xs[k] for k in e.inputs], xs[e.key], e)
        elseif !isempty(src)
            arrow = !isempty(e.next) ? "" : e.operation == :binding ? "⇠" : "←"
            flowtextlist(put, line, src, arrow, inset, cols)
        end
        body = grid || !isempty(src)
        for (s, color, sep) in notes
            if body
                w = textwidth(s)
                col+textwidth(sep)+w <= cols ? put(sep) : line(clamp(cols-w, 0, inset))
            end
            put(s, color)
            body = true
        end
    end
    nothing
end
