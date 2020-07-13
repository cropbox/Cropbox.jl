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
    #HACK: prevent trimWidth from TerminalMenus (much larger padding due to color escape)
    #TODO: remove hack no longer needed in REPL.TerminalMenus
    w = Terminals.width(TerminalMenus.terminal)
    v = repr(value(m); context=:maxlength => w - length(l) - 20)
    isempty(l) ? v : "$l $(Box.DARK_GRAY_FG("=")) $v"
end

dive(s::System, t) = dive(map(zip(fieldnamesalias(s), s)) do ((n, a), v)
    k = string(n)
    l = "$(Box.BLUE_FG(k))"
    !isnothing(a) && (l *= " $(Box.DARK_GRAY_FG("($a)"))")
    MenuItem(k, l, v)
end, t)
dive(s::Vector{<:System}, t) = dive(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s)), t)
dive(s::State{<:Vector}, t) = dive(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s')), t)
dive(s::State, t) = dive(s', t)
dive(l::Vector{MenuItem}, t) = begin
    isempty(l) && return
    term = TerminalMenus.terminal
    o = term.out_stream
    while true
        #TODO: remember current cursor position (supported by REPL.TerminalMenus in Julia 1.6)
        println(o, t)
        M = TerminalMenus.RadioMenu(text.(l), pagesize=40)
        i = TerminalMenus.request(M)
        n = min(length(l), M.pagesize)
        #HACK: for single option menu?
        n == 1 && (n += 1)
        for _ in 0:n
            print(o, "\x1b[999D\x1b[1A") # move up
            print(o, "\x1b[2K") # clear line
        end
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
    b = IOBuffer()
    println(b, t)
    show(b, MIME("text/plain"), v)
    println(b)
    n = countlines(seekstart(b))
    print(o, String(take!(b)))
    Terminals.raw!(term, true) && print(o, "\x1b[?25l") # hide cursor
    c = TerminalMenus.readKey(i)
    Terminals.raw!(term, false) && print(o, "\x1b[?25h") # unhide cursor
    for _ in 1:n
        print(o, "\x1b[999D\x1b[1A") # move up
        print(o, "\x1b[2K") # clear line
    end
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
