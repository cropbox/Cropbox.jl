# Run source-only checks with Julia, or pass --built after a fresh docs build.
# docs/make.jl calls the built-output checks after makedocs and before deployment.
# Only the standard library is needed. See checks/README.md for local usage.

using Test

urlpath(path) = replace(path, '\\' => '/')

function check_navigation(; docs = normpath(joinpath(@__DIR__, "..")), built = false)
    source = joinpath(docs, "src")
    output = built ? joinpath(docs, "build") : source
    navigation = read(joinpath(docs, "make.jl"), String)
    pages = [m.captures[1] for m in eachmatch(r"=>\s*\"([^\"]+\.md)\"", navigation)]
    sources = sort([
        urlpath(relpath(joinpath(directory, file), source))
        for (directory, _, files) in walkdir(source)
        for file in files if endswith(file, ".md")
    ])

    @testset "Documentation navigation" begin
        @test isdir(output)
        @test urlpath("tutorials\\growth.md") == "tutorials/growth.md"
        @test urlpath("tutorials/growth.md") == "tutorials/growth.md"
        @test !isempty(pages)
        @test length(pages) == length(unique(pages))
        @test sort(pages) == sources
        for page in pages
            @test isfile(joinpath(source, page))
        end
    end

    # Documenter discovers the logo automatically; CSS and favicon are listed
    # in HTML(assets=...). Other static assets need a page or CSS reference.
    referenced = Set(["assets/logo.svg"])
    for list in eachmatch(r"assets\s*=\s*\[([^\]]*)\]", navigation)
        for asset in eachmatch(r"\"([^\"]+)\"", list.captures[1])
            push!(referenced, asset.captures[1])
        end
    end

    @testset "Documentation images" begin
        for page in sources
            text = read(joinpath(source, page), String)
            for match in eachmatch(r"!\[[^\]]*\]\(([^\s)]+)\)", text)
                target = match.captures[1]
                startswith(target, "https://") && continue
                startswith(target, "http://") && continue
                image = first(split(target, '#'))
                relative = urlpath(normpath(joinpath(dirname(page), image)))
                # @example files live beside their page in the build tree.
                # Check the actual output, not a guessed filename exception.
                @test isfile(joinpath(output, relative))
                push!(referenced, relative)
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
            relative = urlpath(normpath(joinpath(dirname(asset), target)))
            push!(referenced, relative)
        end
    end

    @testset "Referenced documentation assets" begin
        @test isempty(setdiff(assets, referenced))
        for asset in referenced
            @test isfile(joinpath(output, asset))
        end
    end

    println("Checked $(length(pages)) navigation entries and $(length(assets)) static assets.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    check_navigation(; built = "--built" in ARGS)
end
