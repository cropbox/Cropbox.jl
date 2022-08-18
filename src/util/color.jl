import Crayons
import Highlights

function Highlights.Format.render(io::IO, ::MIME"text/ansi", tokens::Highlights.Format.TokenIterator)
    for (str, id, style) in tokens
        fg = style.fg.active ? map(Int, (style.fg.r, style.fg.g, style.fg.b)) : nothing
        bg = style.bg.active ? map(Int, (style.bg.r, style.bg.g, style.bg.b)) : nothing
        crayon = Crayons.Crayon(
            foreground = fg,
            background = bg,
            bold       = style.bold,
            italics    = style.italic,
            underline  = style.underline,
        )
        print(io, crayon, str, inv(crayon))
    end
end

writecodehtml(filename::AbstractString, source; lexer=Highlights.Lexers.JuliaLexer, theme=Highlights.Themes.TangoTheme) = begin
    open(filename, "w") do io
        print(io, """
        <style>
            @import url(https://cdn.jsdelivr.net/gh/tonsky/FiraCode@4/distr/fira_code.css);
            pre.hljl { font-family: 'Fira Code'; font-size: x-small }
        </style>
        """)
        Highlights.stylesheet(io, MIME("text/html"), theme)
        Highlights.highlight(io, MIME("text/html"), source, lexer, theme)
   end
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
