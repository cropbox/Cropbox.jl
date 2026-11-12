# Run with Julia; no packages outside the standard library are needed:
#   julia docs/checks/navigation.jl
# Documenter's build checks @ref links. This check also catches source pages
# omitted from a pagesonly=true navigation, missing images, and unused assets.

using Test

urlpath(path) = replace(path, '\\' => '/')

docs = normpath(joinpath(@__DIR__, ".."))
source = joinpath(docs, "src")
navigation = read(joinpath(docs, "make.jl"), String)
pages = [m.captures[1] for m in eachmatch(r"=>\s*\"([^\"]+\.md)\"", navigation)]
sources = sort([
    urlpath(relpath(joinpath(directory, file), source))
    for (directory, _, files) in walkdir(source)
    for file in files if endswith(file, ".md")
])

@testset "Documentation navigation" begin
    @test urlpath("tutorials\\growth.md") == "tutorials/growth.md"
    @test urlpath("tutorials/growth.md") == "tutorials/growth.md"
    @test !isempty(pages)
    @test length(pages) == length(unique(pages))
    @test sort(pages) == sources
    for page in pages
        @test isfile(joinpath(source, page))
    end
end

# Documenter discovers the logo automatically; CSS and favicon are listed in
# HTML(assets=...). Other static assets must be referenced by a page or CSS.
referenced = Set(["assets/logo.svg"])
for list in eachmatch(r"assets\s*=\s*\[([^\]]*)\]", navigation)
    for asset in eachmatch(r"\"([^\"]+)\"", list.captures[1])
        push!(referenced, asset.captures[1])
    end
end

@testset "Static documentation images" begin
    for page in sources
        path = joinpath(source, page)
        text = read(path, String)
        for match in eachmatch(r"!\[[^\]]*\]\(([^\s)]+)\)", text)
            target = match.captures[1]
            startswith(target, "https://") && continue
            startswith(target, "http://") && continue
            image = first(split(target, '#'))
            image_path = normpath(joinpath(dirname(path), image))
            @test isfile(image_path)
            push!(referenced, urlpath(relpath(image_path, source)))
        end
    end
end

assets = sort([
    urlpath(relpath(joinpath(directory, file), source))
    for (directory, _, files) in walkdir(joinpath(source, "assets"))
    for file in files
])
for asset in assets
    endswith(asset, ".css") || continue
    path = joinpath(source, asset)
    for match in eachmatch(r"url\(\s*['\"]?([^'\")\s]+)", read(path, String))
        target = match.captures[1]
        occursin(r"^(?:https?:|data:|//|#)", target) && continue
        target = first(split(target, '#'))
        push!(referenced, urlpath(relpath(normpath(joinpath(dirname(path), target)), source)))
    end
end

@testset "Referenced documentation assets" begin
    @test isempty(setdiff(assets, referenced))
    for asset in referenced
        @test isfile(joinpath(source, asset))
    end
end

println("Checked $(length(pages)) navigation entries and $(length(assets)) static assets.")
