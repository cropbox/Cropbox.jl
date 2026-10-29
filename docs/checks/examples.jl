# Run with the documentation environment:
#   julia --project=docs docs/checks/examples.jl
#
# Build a temporary copy using only the visible @example lines. This catches
# essential setup accidentally marked # hide, while using Documenter's normal
# graphical display environment. Ordinary Julia fences may be syntax fragments
# and are not executed. No generated files are written into the checkout.

using Cropbox
using Documenter

source = normpath(joinpath(@__DIR__, "..", "src"))
println("Cropbox: ", pkgdir(Cropbox))

mktempdir() do temporary
    visible_source = joinpath(temporary, "src")
    cp(source, visible_source)
    pages = String[]
    blocks = 0
    for (directory, _, files) in walkdir(visible_source), file in files
        endswith(file, ".md") || continue
        page = joinpath(directory, file)
        push!(pages, relpath(page, visible_source))
        text = read(page, String)
        visible = replace(text, r"^```@example[^\n]*\n.*?^```"ms => block -> begin
            blocks += 1
            join(filter(line -> !occursin(r"#\s*hide\s*$", line), split(block, '\n')), '\n')
        end)
        write(page, visible)
    end
    @assert blocks > 0
    makedocs(
        sitename = "Cropbox visible example check",
        source = visible_source,
        build = joinpath(temporary, "build"),
        pages = sort(pages),
        format = Documenter.HTML(prettyurls = false),
        remotes = nothing,
    )
    println("Checked $blocks visible example blocks across $(length(pages)) pages.")
end
