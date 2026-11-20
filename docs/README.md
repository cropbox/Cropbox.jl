<a href="https://cropbox.github.io/Cropbox.jl/stable/"><img src="src/assets/logo.svg" alt="Cropbox" width="150"></a>

# Cropbox documentation

Welcome to the Cropbox documentation. Cropbox is a declarative modeling
framework for building and running crop models in Julia. A model describes its
components, variables, equations, data sources, and update rules; Cropbox turns
that specification into simulations that can be visualized and evaluated.

**[Open the current documentation →](https://cropbox.github.io/Cropbox.jl/dev/)**

This directory follows the `main` branch and is published at the development
site. For the registered package release, use the
[stable documentation](https://cropbox.github.io/Cropbox.jl/stable/), which may
have an older layout. Both sites are published automatically through GitHub Pages.

## Where to begin

After [installation](https://cropbox.github.io/Cropbox.jl/dev/installation/),
choose one starting point:

- **[Build a logistic growth model](https://cropbox.github.io/Cropbox.jl/dev/tutorials/quickstart/).**
  Compare growth rates, then continue along the [Learning Path](https://cropbox.github.io/Cropbox.jl/dev/tutorials/).
- **[Run the garlic model](https://cropbox.github.io/Cropbox.jl/dev/tutorials/garlic/).**
  Use its packaged cultivar and weather to compare leaf and bulb dry mass.

For the reasoning behind the examples, see
[How Cropbox Works](https://cropbox.github.io/Cropbox.jl/dev/concepts/overview/).
For exact syntax and options, use the
[Reference](https://cropbox.github.io/Cropbox.jl/dev/reference/overview/).

## Model tutorials

The documentation includes worked examples that connect model specification,
simulation, visualization, and interpretation:

- garlic phenology, leaf development, biomass, carbon flow, and planting-date
  scenarios;
- leaf gas exchange across CO₂, light, temperature, nitrogen, and water
  conditions;
- CropRootBox root-system architecture, hierarchy traversal, rendering, and
  geometry export;
- SimpleCrop, a small model adapted from DSSAT teaching material that shows
  how phenology, canopy growth, and biomass partitioning fit together;
- the layered soil-water example and pedotransfer functions from the Cropbox
  test suite.

Each tutorial introduces the scientific source, shows the main configuration
and simulation workflow, and includes figures generated from the model output.

## Documentation map

| Section | What it contains |
|---|---|
| **Start Here** | overview, installation, and a first runnable model |
| **Core Concepts** | modeling workflow, system composition, and model execution |
| **Tutorials** | a sequential learning path, model studies, and related papers and workshops |
| **Guides** | task-oriented workflows, project setup, troubleshooting, and performance advice |
| **Reference** | full DSL and behavior rules, API arguments, examples, results, and figures |

For the newest material merged into `main`, use the development site. For research
and teaching tied to a released Cropbox version, use the stable site.
