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
