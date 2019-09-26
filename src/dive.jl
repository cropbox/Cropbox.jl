# REPL.TerminalMenus doesn't support single-option menu
using TerminalMenus

struct MenuItem
    name::Symbol
    value
end

dive(s::System) = begin
    nav(s::System, n) = nav(map(a -> (a, s[a]), [collectible(s)..., updatable(s)...]), n)
    nav(s::Produce, n) = nav(collect(enumerate(value(s))), n)
    nav(s::State, n) = nav(value(s), n)
    nav(l::Vector, n) = begin
        isempty(l) && return

        label(v::Tuple) = string(v[1])
        content(v::Tuple) = v[2]
        item(v::Tuple) = "$(label(v)) = $(content(v))"

        label(v) = ""
        content(v) = v
        item(v) = "$(content(v))"

        while true
            println(n)
            i = RadioMenu(item.(l), pagesize=40) |> request
            println()
            if i > 0
                v = l[i]
                nav(content(v), n * " > " * label(v))
            else
                break
            end
        end
    end
    nav(v, n) = throw(value(v))
    try
        nav(s, name(s))
    catch e
        !isa(e, InterruptException) && return e
    end
    nothing
end

export dive
