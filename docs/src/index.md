# Cropbox

Cropbox is a declarative framework for building and running crop models in Julia.
You describe model components, variables, equations, data sources, and update
rules. Cropbox orders those calculations, carries configuration and time through
the model, and collects simulation output into data frames.

```@example home
using Cropbox

@system Growth(Controller) begin
    rate: growth_rate => 1.5 ~ preserve(parameter, u"g/hr")
    mass(rate)               ~ accumulate(u"g")
end

result = simulate(Growth; stop = 3u"hr")
```

This is a small example, but the same workflow is used in coupled leaf gas
exchange, garlic growth, SimpleCrop, layered soil, and root architecture models.

## Choose a path

- New to Cropbox: start with [Quick Start](@ref quick-start).
- Building a model: read [How Cropbox Works](@ref cropbox-concepts), then
  [Weather-driven Phenology](@ref phenology-tutorial).
- Using an existing model: go directly to the
  [Leaf Gas Exchange](@ref leaf-gas-exchange-tutorial),
  [Garlic](@ref garlic-tutorial), [SimpleCrop](@ref simplecrop-tutorial),
  [Soil Water Transport](@ref soil-water-transport-tutorial), or
  [CropRootBox](@ref croprootbox-tutorial) tutorial.
- Looking up syntax: use [DSL Syntax](@ref dsl-syntax) and
  [Behaviors and Tags](@ref behaviors-and-tags).
- Maintaining or extending a model package: combine
  [Systems and Composition](@ref system), [DSL Syntax](@ref dsl-syntax),
  [Inspection](@ref Inspection1), and
  [Dynamic Hierarchies](@ref dynamic-hierarchies) as needed.
- Debugging or optimizing a model: see [Frequently Asked Questions](@ref faq),
  [Common Mistakes](@ref common-mistakes), and
  [Performance and Reproducibility](@ref performance-guide).

## The normal workflow

Cropbox follows the same three-phase workflow used in Cropbox courses:

| Phase | Goal | Main tools |
|---|---|---|
| Specification | Define processes, states, inputs, and dependencies. | `@system`, behaviors, tags, units |
| Simulation | Apply scenarios, advance state, and collect selected output. | `parameters`, `@config`, `instance`, `simulate` |
| Visualization and evaluation | Explore predictions and compare them with observations. | `visualize`, `evaluate`, `calibrate` |

Cropbox deliberately separates model equations from scenario configuration.
One model definition can therefore be reused with different weather data,
cultivars, management settings, and parameter combinations. See
[How Cropbox Works](@ref cropbox-concepts) for the complete workflow diagram and
the role of each phase.

## Model examples

The worked tutorials progress from framework mechanics to coupled applications:

| Tutorial | What it demonstrates |
|---|---|
| [Logistic Growth](@ref logistic-growth-tutorial) | translating a differential equation into states, rates, and configuration |
| [Weather-driven Phenology](@ref phenology-tutorial) | calendar time, tabular weather input, thermal time, and a biological stop condition |
| [Predator–Prey Model](@ref lotka-volterra-tutorial) | Lotka–Volterra equations, coupled accumulated states, mixin extension, and observation-based fitting |
| [Leaf Gas Exchange](@ref leaf-gas-exchange-tutorial) | inspecting a coupled biochemical model across configured environmental ranges |
| [Garlic Growth Model](@ref garlic-tutorial) | whole-plant composition, daily output, and dynamic organs |
| [SimpleCrop](@ref simplecrop-tutorial) | running a compact crop model and reading development, growth, and environmental output |
| [Soil Water Transport](@ref soil-water-transport-tutorial) | layered storage and fluxes, pedotransfer functions, and a test-suite simulation |
| [Root System Architecture](@ref croprootbox-tutorial) | stochastic configuration, dynamic systems, geometry, and custom summaries |

These examples are drawn from Cropbox tests, courses, and workshops. The
[Model Gallery](@ref Gallery) links their package repositories and additional
workshop material.

After a model can be simulated and visualized, continue with
[Evaluate and Calibrate Models](@ref evaluation-tutorial). It belongs to the
workflow that compares predictions with observations, rather than to the
sequence of model examples.

## Citation

When using Cropbox in your work, please cite the following paper:

Yun K, Kim S-H (2023) “Cropbox: a declarative crop modelling framework.”
*in silico Plants* 5(1), diac021.
[doi:10.1093/insilicoplants/diac021](https://doi.org/10.1093/insilicoplants/diac021)

```bibtex
@article{Cropbox2023,
    title = {Cropbox: a declarative crop modelling framework},
    author = {Yun, Kyungdahm and Kim, Soo-Hyung},
    journal = {in silico Plants},
    volume = {5},
    number = {1},
    year = {2023},
    doi = {10.1093/insilicoplants/diac021}
}
```

The repository also keeps this entry in
[`CITATION.bib`](https://github.com/cropbox/Cropbox.jl/blob/main/CITATION.bib).
