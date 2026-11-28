# [Models and Resources](@id Gallery)

These packages demonstrate different Cropbox workflows. Their biological
parameters and model-specific APIs belong to their own repositories; this manual
focuses on the Cropbox concepts shared across them.

## Reproducing an example

The SimpleCrop and Soil Water Transport examples run when this manual is
built. The Leaf Gas Exchange, Garlic, and Root System Architecture pages
instead show saved figures and give the commands to run in each model's own
environment; a successful manual build does not rerun those three models.
To repeat your own run, keep the input data and configuration with the Julia
version and project's `Manifest.toml`. For a stochastic model, keep the seed
as well. To reproduce a published result, start with the study's archived
code and data where available.

## [LeafGasExchange.jl](https://github.com/cropbox/LeafGasExchange.jl)

Coupled C₃/C₄ photosynthesis, stomatal conductance, and leaf energy balance.
Useful for response curves, factorial environmental sweeps, nonlinear solvers,
and observation-based parameter work. Start with the
[Leaf Gas Exchange tutorial](@ref leaf-gas-exchange-tutorial).

The [plants2020 companion repository](https://github.com/cropbox/plants2020)
contains the notebook, data, and rendered output distributed with the original
*Plants* study. Use it to reproduce that publication; use the tutorial above
for the current package API.

## [Garlic.jl](https://github.com/cropbox/Garlic.jl)

A process-based hardneck garlic model integrating phenology, weather,
radiation, gas exchange, carbon balance, organ morphology, and biomass. It
demonstrates large-system composition and dynamic leaves. Start with the
[Garlic tutorial](@ref garlic-tutorial).

## [SimpleCrop.jl](https://github.com/cropbox/SimpleCrop.jl)

A compact crop model based on the DSSAT modular-model teaching material. Use
the [SimpleCrop tutorial](@ref simplecrop-tutorial) to trace how weather and
irrigation inputs connect to canopy growth, soil water, and biomass.

## Cropbox layered-soil test model

Cropbox itself contains a multi-layer soil-water example used by the framework
test suite. It combines pedotransfer functions, layer storage, hydraulic heads,
and surface, inter-layer, and lower-boundary fluxes. The
[Soil Water Transport tutorial](@ref soil-water-transport-tutorial) runs that implementation
directly and explains its current scope.

## [CropRootBox.jl](https://github.com/cropbox/CropRootBox.jl)

A dynamic root system architecture model inspired by CRootBox. It demonstrates
stochastic parameters, dynamic production, geometry, custom output collection,
and VTK/STL export. Start with [Root System Architecture](@ref
croprootbox-tutorial).

## [LegacyCropModels.jl](https://github.com/cropbox/LegacyCropModels.jl)

Cropbox implementations of the LINTUL crop models. Compare potential production
with growth limited by water or by both water and nitrogen.

## Other crop models

- [Cabbage.jl](https://github.com/cropbox/Cabbage.jl): a Cropbox port of the pycabbage model.
- [Radish.jl](https://github.com/cropbox/Radish.jl): a radish growth model.

Access to these repositories may be restricted.

## Talks

- [JuliaCon 2022: “Cropbox.jl: A Declarative Crop Modeling Framework”](https://youtu.be/l43ldy_L35A)

## Workshops and courses

The Cropbox organization hosts workshop repositories covering small growth
models, photosynthesis, phenology, model integration, SIMPLE, Garlic, and other
crop applications:

- [Cropbox Workshop 2025](https://github.com/cropbox/cropbox-workshop-2025)
- [Cropbox Workshop 2022 (Korea)](https://github.com/cropbox/cropbox-workshop-2022)
- [Cropbox Workshop 2022 (Taiwan)](https://github.com/cropbox/cropbox-workshop-2022-tw)
- [Cropbox Workshop 2021](https://github.com/cropbox/cropbox-workshop-2021)
- [KSAFM 2020 Cropbox Tutorial](https://github.com/cropbox/cropbox-tutorial-KSAFM2020)
- [UW SEFS 508 Plant Modeling](https://github.com/uwkimlab/plant_modeling)

Workshop notebooks are valuable worked examples but may target older package
versions. Use the workflow and scientific explanation, then verify current
syntax against this manual and the model's tests.
