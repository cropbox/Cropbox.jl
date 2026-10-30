import Crayons
import JuliaSyntaxHighlighting

highlightcode(io::IO, ::MIME"text/plain", source) = print(io, JuliaSyntaxHighlighting.highlight(source))
highlightcode(io::IO, m::MIME"text/html", source) = begin
    print(io, """
    <style>
        @import url(https://cdn.jsdelivr.net/gh/tonsky/FiraCode@4/distr/fira_code.css);
    </style>
    <pre style="font-family: 'Fira Code'; font-size: x-small">""")
    show(io, m, JuliaSyntaxHighlighting.highlight(source))
    print(io, "</pre>")
end

writecodehtml(filename::AbstractString, source) = open(filename, "w") do io
    highlightcode(io, MIME("text/html"), source)
end

abstract type TokenColor end
struct SystemColor <: TokenColor end
struct VarColor <: TokenColor end
struct StateColor <: TokenColor end
struct NonStateColor <: TokenColor end
struct MiscColor <: TokenColor end
struct NoColor <: TokenColor end

tokencolor(c::TokenColor; color::Bool) = tokencolor(color ? c : NoColor())
tokencolor(::SystemColor) = Crayons.Box.LIGHT_MAGENTA_FG
tokencolor(::VarColor) = Crayons.Box.LIGHT_BLUE_FG
tokencolor(::StateColor) = Crayons.Box.CYAN_FG
tokencolor(::NonStateColor) = Crayons.Box.LIGHT_GREEN_FG
tokencolor(::MiscColor) = Crayons.Box.DARK_GRAY_FG
tokencolor(::NoColor) = Crayons.Box.DEFAULT_FG

# compatibility for dive() where escapes are mandatory
system_color(s) = tokencolor(SystemColor())(s)
variable_color(s) = tokencolor(VarColor())(s)
state_color(s) = tokencolor(StateColor())(s)
non_state_color(s) = tokencolor(NonStateColor())(s)
misc_color(s) = tokencolor(MiscColor())(s)
