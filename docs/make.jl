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
            "Systems and Simulation Lifecycle" => "concepts/lifecycle.md",
        ],
        "Learn by Example" => [
            "Logistic Growth" => "tutorials/growth.md",
            "Build a Weather-driven Model" => "tutorials/phenology.md",
            "Coupled Population Dynamics" => "tutorials/lotka-volterra.md",
            "Leaf Gas Exchange" => "tutorials/leafgasexchange.md",
            "Garlic Growth Model" => "tutorials/garlic.md",
            "Soil Water and SimpleCrop" => "tutorials/soilwater.md",
            "Root System Architecture" => "tutorials/croprootbox.md",
            "Evaluation and Calibration" => "tutorials/evaluation.md",
        ],
        "Workflows" => [
            "Configure Models and Scenarios" => "howto/configuration.md",
            "Run Simulations and Shape Output" => "howto/simulation.md",
            "Inspect and Visualize Models" => "howto/inspection.md",
        ],
        "DSL and API Reference" => [
            "DSL Syntax" => "reference/dsl.md",
            "Behaviors and Tags" => "reference/behaviors.md",
            "Systems" => "guide/system.md",
            "Declarations" => "reference/declaration.md",
            "Simulation API" => "reference/simulation.md",
            "Visualization API" => "reference/visualization.md",
            "Inspection API" => "reference/inspection.md",
            "Values, Units, and Structure" => "reference/utilities.md",
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
