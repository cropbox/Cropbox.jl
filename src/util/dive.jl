#TODO: single-option menu from REPL.TerminalMenus: https://github.com/JuliaLang/julia/pull/36369
import TerminalMenus
import REPL.Terminals
import Crayons.Box

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
    isempty(l) ? v : "$l $(Box.DARK_GRAY_FG("=")) $v"
end

dive(s::System, t) = begin
    d = Dict(fieldnamesalias(s))
    label(k) = begin
        n = string(k)
        a = d[k]
        l = "$(Box.BLUE_FG(n))"
        !isnothing(a) && (l *= " $(Box.DARK_GRAY_FG("($a)"))")
        l
    end
    l = fieldnamesunique(s) |> collect
    dive(map(a -> MenuItem(string(a), label(a), s[a]), l), t)
end
dive(s::Vector{<:System}, t) = dive(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s)), t)
dive(s::Tabulate, t) = dive(s', t)
dive(s::Call, t) = dive(s', t)
dive(s::Produce, t) = dive(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s')), t)
dive(s::State, t) = dive(map(v -> MenuItem("", "", v), s'), t)
dive(l::Vector{MenuItem}, t) = begin
    isempty(l) && return
    while true
        println(t)
        M = TerminalMenus.RadioMenu(text.(l), pagesize=40)
        i = TerminalMenus.request(M)
        println()
        if i > 0
            v = l[i]
            dive(value(v), "$t $(Box.DARK_GRAY_FG(">")) $(Box.MAGENTA_FG(name(v)))")
        else
            break
        end
    end
end
dive(m::MenuItem, t) = dive(value(m), t)
dive(v, t) = begin
    term = TerminalMenus.terminal
    i = term.in_stream
    o = term.out_stream
    println(o, t)
    show(o, MIME("text/plain"), v)
    print(o, "\n^ ")
    Terminals.raw!(term, true) && print(o, "\x1b[?25l") # hide cursor
    c = TerminalMenus.readKey(i)
    Terminals.raw!(term, false) && print(o, "\x1b[?25h") # unhide cursor
    println(o)
    if c == 13 # enter
        throw(v)
    elseif c == 3 # ctrl-c
        throw(InterruptException())
    end
end

dive(s::System) = begin
    try
        dive(s, "<$(Box.MAGENTA_FG("$(namefor(s))"))>")
    catch e
        !isa(e, InterruptException) && return e
    end
    nothing
end

export dive
