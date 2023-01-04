using Documenter
using Cropbox

makedocs(
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://cropbox.github.io/Cropbox.jl/stable/",
        assets = ["assets/favicon.ico"],
        analytics = "UA-192782823-1",
    ),
    sitename = "Cropbox.jl",
    pages = [
        "Introduction" => [
            "Cropbox" => "index.md",
            "Installation" => "installation.md"
        ],
        "Guide" => [
            "System" => "guide/system.md",
            "Variable" => "guide/variable.md",
            "Configuration" => "guide/configuration.md",
            "Simulation" => "guide/simulation.md",
            "Visualization" => "guide/visualization.md",
            "Inspection" => "guide/inspection.md"
        ],
        "Tutorials" => [
            "Growing Degree-Day" => "tutorials/gdd.md",
            "Lotka-Volterra Equations" => "tutorials/lotkavolterra.md",
        ],
        "Gallery" => "gallery.md",
        "Reference" => [
            "Index" => "reference/index.md",
            "Declaration" => "reference/declaration.md",
            "Simulation" => "reference/simulation.md",
            "Visualization" => "reference/visualization.md",
            "Inspection" => "reference/inspection.md",
        ],
        "Frequently Asked Questions" => "faq.md",
    ],
)

deploydocs(
    repo = "github.com/cropbox/Cropbox.jl.git",
    devbranch = "main",
)
