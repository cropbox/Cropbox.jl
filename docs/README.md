<a href="https://cropbox.github.io/Cropbox.jl/stable/"><img src="src/assets/logo.svg" alt="Cropbox" width="150"></a>

# Cropbox documentation

Welcome to the Cropbox documentation. Cropbox is a declarative modeling
framework for building and running crop models in Julia. A model describes its
components, variables, equations, data sources, and update rules; Cropbox turns
that specification into simulations that can be visualized and evaluated.

**[Open the stable documentation →](https://cropbox.github.io/Cropbox.jl/stable/)**

The latest documentation from the `main` branch is available at the
[development site](https://cropbox.github.io/Cropbox.jl/dev/). Both sites are
published automatically through GitHub Pages.

## Where to begin

- New to Cropbox? Start with the [overview](https://cropbox.github.io/Cropbox.jl/stable/),
  [installation](https://cropbox.github.io/Cropbox.jl/stable/installation/), and
  [quick start](https://cropbox.github.io/Cropbox.jl/stable/tutorials/quickstart/).
- Want to understand the framework? Read
  [How Cropbox Works](https://cropbox.github.io/Cropbox.jl/stable/concepts/overview/)
  and the
  [system lifecycle](https://cropbox.github.io/Cropbox.jl/stable/concepts/lifecycle/).
- Want to build a model step by step? Follow the logistic-growth,
  weather-driven phenology, and coupled-population tutorials under
  **Learn by Example**.
- Already have a model? Use the task-oriented guides for configuration,
  simulation, inspection, visualization, evaluation, and calibration.
- Looking for exact syntax or options? Go directly to the DSL and public API
  reference.

## Model tutorials

The documentation includes worked examples that connect model specification,
simulation, visualization, and interpretation:

- leaf gas exchange across CO₂, light, temperature, nitrogen, and water
  conditions;
- garlic phenology, leaf development, biomass, carbon flow, and planting-date
  scenarios;
- SimpleCrop growth, soil-water fluxes, stress, water balance, and irrigation;
- CropRootBox root-system architecture, hierarchy traversal, rendering, and
  geometry export.

Each tutorial introduces the scientific source, shows the main configuration
and simulation workflow, and includes figures generated from the model output.

## Documentation map

| Section | What it contains |
|---|---|
| **Start Here** | overview, installation, and a first runnable model |
| **Core Concepts** | systems, variables, dependencies, behaviors, context, and simulation lifecycle |
| **Learn by Example** | progressively larger models and scientific applications |
| **Workflows** | practical recipes for configuration, simulation, inspection, and output |
| **DSL and API Reference** | declaration grammar, behaviors, tags, functions, components, and plotting variants |
| **Troubleshooting** | FAQ, common mistakes, performance, and reproducibility advice |
| **Model Gallery** | related model packages, workshops, and learning resources |

For the newest material under review, use the development site. For research
and teaching tied to a released Cropbox version, use the stable site.
