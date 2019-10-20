# REPL.TerminalMenus doesn't support single-option menu
using TerminalMenus
using Crayons.Box

struct MenuItem
    name::String
    label::String
    value
end

name(m::MenuItem) = m.name
label(m::MenuItem) = isempty(m.label) ? m.name : m.label
value(m::MenuItem) = m.value
text(m::MenuItem) = begin
    l = label(m)
    v = value(m) |> repr
    isempty(l) ? v : "$l $(DARK_GRAY_FG("=")) $v"
end

dive(s::System) = begin
    nav(s::System, t) = begin
        d = Dict(fieldnamesalias(s))
        label(k) = begin
            n = string(k)
            a = join(d[k], ", ")
            isempty(a) ? "$(BLUE_FG(n))" : "$(BLUE_FG(a)) $(DARK_GRAY_FG("($n)"))"
        end
        l = fieldnames(typeof(s)) |> collect
        nav(map(a -> MenuItem(string(a), label(a), s[a]), l), t)
    end
    nav(s::Vector{<:System}, t) = nav(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s)), t)
    nav(s::Produce, t) = nav(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(value(s))), t)
    nav(s::State, t) = nav(map(v -> MenuItem("", "", v), value(s)), t)
    nav(l::Vector{MenuItem}, t) = begin
        isempty(l) && return
        while true
            println(t)
            i = RadioMenu(text.(l), pagesize=40) |> request
            println()
            if i > 0
                v = l[i]
                nav(value(v), "$t $(DARK_GRAY_FG(">")) $(MAGENTA_FG(name(v)))")
            else
                break
            end
        end
    end
    nav(v, t) = throw(value(v))
    try
        nav(s, string(MAGENTA_FG(name(s))))
    catch e
        !isa(e, InterruptException) && return e
    end
    nothing
end

export dive
