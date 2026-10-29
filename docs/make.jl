using Documenter
using Cropbox

makedocs(
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://cropbox.github.io/Cropbox.jl/stable/",
        assets = ["assets/favicon.ico", "assets/custom.css"],
        analytics = "UA-192782823-1",
    ),
    sitename = "Cropbox.jl",
    pagesonly = true,
    pages = [
        "Start Here" => [
            "Overview" => "index.md",
            "Installation" => "installation.md",
            "Quick Start" => "tutorials/quickstart.md",
        ],
        "Core Concepts" => [
            "How Cropbox Works" => "concepts/overview.md",
            "Systems and Composition" => "guide/system.md",
            "Model Execution" => "concepts/lifecycle.md",
            "DSL Syntax" => "reference/dsl.md",
            "Behaviors and Tags" => "reference/behaviors.md",
        ],
        "Learn by Example" => [
            "Logistic Growth" => "tutorials/growth.md",
            "Weather-driven Phenology" => "tutorials/phenology.md",
            "Predator–Prey Model" => "tutorials/lotka-volterra.md",
            "Leaf Gas Exchange" => "tutorials/leafgasexchange.md",
            "Garlic Growth Model" => "tutorials/garlic.md",
            "SimpleCrop" => "tutorials/simplecrop.md",
            "Soil Water Transport" => "tutorials/soilwater.md",
            "Root System Architecture" => "tutorials/croprootbox.md",
        ],
        "Workflows" => [
            "Configure Models and Scenarios" => "howto/configuration.md",
            "Run Simulations and Shape Output" => "howto/simulation.md",
            "Inspect and Visualize Models" => "howto/inspection.md",
            "Evaluate and Calibrate Models" => "tutorials/evaluation.md",
        ],
        "API Reference" => [
            "Declarations" => "reference/declaration.md",
            "Simulation API" => "reference/simulation.md",
            "Visualization API" => "reference/visualization.md",
            "Inspection API" => "reference/inspection.md",
            "Values and Units" => "reference/utilities.md",
            "Dynamic Hierarchies" => "reference/hierarchy.md",
            "Built-in Model Components" => "reference/components.md",
            "API Index" => "reference/index.md",
        ],
        "Troubleshooting" => [
            "Frequently Asked Questions" => "faq.md",
            "Common Mistakes" => "troubleshooting/common-mistakes.md",
            "Performance and Reproducibility" => "troubleshooting/performance.md",
        ],
        "Model Gallery" => "gallery.md",
    ]
)

deploydocs(
    repo = "github.com/cropbox/Cropbox.jl.git",
    devbranch = "main",
)
