#TODO: use vendored TerminalMenus until new version released with Julia 1.6: https://github.com/JuliaLang/julia/pull/36369
#import REPL.TerminalMenus
include("../../lib/TerminalMenus/TerminalMenus.jl")
import REPL.Terminals
import Crayons.Box

struct MenuItem{V}
    name::String
    label::String
    value::V
end

name(m::MenuItem) = m.name
label(m::MenuItem) = isempty(m.label) ? m.name : m.label
value(m::MenuItem) = m.value
text(m::MenuItem) = begin
    l = label(m)
    w = Terminals.width(TerminalMenus.terminal)
    #HACK: length(l) contains escape sequences, so actual line may look shorter
    v = repr(value(m); context=:maxlength => w - length(l))
    isempty(l) ? v : "$l $(Box.DARK_GRAY_FG("=")) $v"
end

title(m::MenuItem{<:System}) = "$(Box.MAGENTA_FG(name(m)))"
title(m::MenuItem{<:State}) = "$(Box.CYAN_FG(name(m)))"
title(m::MenuItem) = "$(Box.GREEN_FG(name(m)))"
title(t::Vector{<:MenuItem}) = begin
    sep = " $(Box.DARK_GRAY_FG(">")) "
    join(title.(t), sep)
end

dive(s::System, t) = dive(map(zip(fieldnamesalias(s), s)) do ((n, a), v)
    k = string(n)
    l = "$(Box.BLUE_FG(k))"
    !isnothing(a) && (l *= " $(Box.DARK_GRAY_FG("($a)"))")
    MenuItem(k, l, v)
end, t)
dive(s::Vector{<:System}, t) = dive(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s)), t)
dive(s::State{<:System}, t) = dive(s', t)
dive(s::State{<:Vector}, t) = dive(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s')), t)
dive(s::State, t) = dive(t) do io
    p = value(t[end-1])
    d = dependency(p)
    k = Symbol(name(t[end]))
    v = d.M[k]
    println(io, "----")
    println(io, string(v.line))
    println(io, "----")
    show(io, MIME("text/plain"), s')
end
dive(l::Vector{<:MenuItem}, t) = begin
    isempty(l) && return
    term = TerminalMenus.terminal
    o = term.out_stream
    i = 1
    while true
        println(o, title(t))
        N = length(l)
        M = TerminalMenus.RadioMenu(text.(l); charset=:unicode, pagesize=N)
        i = TerminalMenus.request(M; cursor=i)
        n = min(N, M.pagesize)
        #HACK: for single option menu?
        n == 1 && (n += 1)
        print(o, repeat("\x1b[9999D\x1b[1A", n+1)) # move up
        print(o, "\x1b[J") # clear lines below
        if i > 0
            v = l[i]
            dive(value(v), [t..., v])
        else
            break
        end
    end
end
dive(m::MenuItem, t) = dive(value(m), t)
dive(v, t) = dive(t) do io
    show(io, MIME("text/plain"), v)
end
dive(f::Function, t) = begin
    term = TerminalMenus.terminal
    i = term.in_stream
    o = term.out_stream
    b = IOBuffer()
    println(b, title(t))
    f(b)
    println(b)
    n = countlines(seekstart(b))
    print(o, String(take!(b)))
    Terminals.raw!(term, true) && print(o, "\x1b[?25l") # hide cursor
    c = TerminalMenus.readkey(i)
    Terminals.raw!(term, false) && print(o, "\x1b[?25h") # unhide cursor
    print(o, repeat("\x1b[9999D\x1b[1A", n)) # move up
    print(o, "\x1b[J") # clear lines below
    if c == 13 # enter
        throw(value(t[end]))
    elseif c == 3 # ctrl-c
        throw(InterruptException())
    end
end

dive(s::System) = begin
    if isdefined(Main, :IJulia) && Main.IJulia.inited
        return look(s)
    end
    try
        dive(s, [MenuItem(string(namefor(s)), "", s)])
    catch e
        !isa(e, InterruptException) && return e
    end
    nothing
end

export dive
