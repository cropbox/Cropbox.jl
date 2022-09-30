using Markdown

WebIO.render(md::Markdown.MD) = blocknode(md)

blocknode(x) = wrapnode(x)
inlinenode(x) = wrapnode(x)

blocknode(md::Markdown.MD) = vbox(map(blocknode, md.content))(className="jl-markdown")
inlinenode(x::AbstractString) = x

blocknode(md::Markdown.Header{n}) where {n} =
     node("h$n", map(inlinenode, md.text)...)

inlinenode(md::Markdown.Code) = node("code", md.code)

blocknode(md::Markdown.Code)  =
    node("pre", md.code)

blocknode(md::Markdown.BlockQuote) =
    blockquote(map(blocknode, md.content))

function blocknode(md::Markdown.List)
    el = md.ordered == -1 ? "ul" : "ol"
    node(el, map(x->node("li", inlinenode.(x)...), md.items)...)
end
blocknode(md::Markdown.Paragraph) =
    node("p", map(inlinenode, md.content)...)

inlinenode(md::Markdown.Paragraph) =
    node("div", map(inlinenode, md.content)...)

inlinenode(md::Markdown.Italic) = node("em", map(inlinenode, md.text)...)
inlinenode(md::Markdown.Bold) = node("span", map(inlinenode, md.text)...)(fontweight("bold"))
inlinenode(md::Markdown.Link) = node("a", map(inlinenode, md.text)..., href=md.url)

inlinenode(md::Markdown.Image) = node("img", src=md.url, alt=md.alt)
blocknode(md::Markdown.Image) = node("img", src=md.url, alt=md.alt)

function katexscope(formula, display)
    imports = ["https://cdn.jsdelivr.net/npm/katex@0.10.1/dist/katex.min.js",
               "https://cdn.jsdelivr.net/npm/katex@0.10.1/dist/katex.min.css"]
    s = Scope(imports=imports)
    formula = strip(formula, '$')
    onimport(s, js"""function (katex) {
             katex.render($formula, this.dom, {displayMode: $display})
             }""")
    s
end

function inlinenode(md::Markdown.LaTeX)
    style(katexscope(md.formula, false)(node("span")), Dict("display"=>"inline"))
end
function blocknode(md::Markdown.LaTeX)
    katexscope(md.formula, true)(node("div"))
end
