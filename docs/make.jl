using Documenter
using Cropbox

makedocs(
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://tomyun.github.io/Cropbox.jl/stable/",
        assets = ["assets/favicon.ico"],
        analytics = "UA-192782823-1",
    ),
    sitename = "Cropbox.jl",
    pages = [
        "Home" => "index.md",
        "Guide" => [
        ],
        "Tutorials" => [
        ],
        "Reference" => [
            "Index" => "reference/index.md",
            "Declaration" => "reference/declaration.md",
            "Simulation" => "reference/simulation.md",
            "Visualization" => "reference/visualization.md",
            "Inspection" => "reference/inspection.md",
        ],
    ],
)

deploydocs(
    repo = "github.com/tomyun/Cropbox.jl.git",
    devbranch = "main",
)
