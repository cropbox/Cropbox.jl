import REPL.TerminalMenus
import REPL.Terminals

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
    isempty(l) ? v : "$l $(misc_color("=")) $v"
end

title(m::MenuItem{<:System}) = "$(system_color(name(m)))"
title(m::MenuItem{<:State}) = "$(state_color(name(m)))"
title(m::MenuItem) = "$(non_state_color(name(m)))"
title(t::Vector{<:MenuItem}) = begin
    sep = " $(misc_color(">")) "
    join(title.(t), sep)
end

dive(s::System, t) = dive(map(zip(fieldnamesalias(s), s)) do ((n, a), v)
    k = string(n)
    l = "$(variable_color(k))"
    !isnothing(a) && (l *= " $(misc_color("($a)"))")
    MenuItem(k, l, v)
end, t)
dive(s::Vector{<:System}, t) = dive(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s)), t)
dive(s::State{<:System}, t) = dive([MenuItem("1", "", s')], t)
dive(s::State{<:Vector}, t) = dive(map(t -> MenuItem(string(t[1]), "", t[2]), enumerate(s')), t)
dive(s::State, t) = dive(t) do io
    look(io, value(t[end-1]), Symbol(name(t[end])))
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
    show(IOContext(io, :limit => true), MIME("text/plain"), v)
end
dive(f::Function, t) = begin
    term = TerminalMenus.terminal
    i = term.in_stream
    o = term.out_stream
    b = IOBuffer()
    #HACK: dive() assumes color terminal
    x = IOContext(b, :color => get(o, :color, true))
    println(x, title(t))
    f(x)
    println(x)
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

"""
    dive(s)

Inspect an instance of system `s` by navigating hierarchy of variables displayed in a tree structure.

Pressing up/down arrow keys allows navigation. Press 'enter' to dive into a deeper level and press 'q' to come back. A leaf node of the tree shows an output of `look` regarding the variable. Pressing 'enter' again would return a variable itself and exit to REPL.

Only works in a terminal environment; not working on Jupyter Notebook.

See also: [`look`](@ref)

# Arguments
- `s::System`: instance of target system.

# Examples
```julia-repl
julia> @system S(Controller) begin
           a => 1 ~ preserve(parameter)
       end;

julia> s = instance(S);

julia> dive(s)
S
 → context = <Context>
   config = <Config>
   a = 1.0
```
"""
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
