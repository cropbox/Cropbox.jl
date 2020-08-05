import Crayons
import Highlights

function Highlights.Format.render(io::IO, ::MIME"text/ansi", tokens::Highlights.Format.TokenIterator)
    for (str, id, style) in tokens
        fg = style.fg.active ? map(Int, (style.fg.r, style.fg.g, style.fg.b)) : :nothing
        bg = style.bg.active ? map(Int, (style.bg.r, style.bg.g, style.bg.b)) : :nothing
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

system_color(s) = Crayons.Box.LIGHT_MAGENTA_FG(s)
variable_color(s) = Crayons.Box.LIGHT_BLUE_FG(s)
state_color(s) = Crayons.Box.CYAN_FG(s)
non_state_color(s) = Crayons.Box.LIGHT_GREEN_FG(s)
misc_color(s) = Crayons.Box.DARK_GRAY_FG(s)
