# [Model Gallery](@id Gallery)

These packages demonstrate different Cropbox workflows. Their biological
parameters and model-specific APIs belong to their own repositories; this manual
focuses on the Cropbox concepts shared across them.

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

A compact modular crop model with phenology, canopy growth, partitioning,
weather input, irrigation, and a soil-water balance. It is the executable model
in [Soil Water and SimpleCrop](@ref soil-water-tutorial).

## [CropRootBox.jl](https://github.com/cropbox/CropRootBox.jl)

A dynamic root system architecture model inspired by CRootBox. It demonstrates
stochastic parameters, dynamic production, geometry, custom output collection,
and VTK/STL export. Start with [Root System Architecture](@ref
croprootbox-tutorial).

## Additional historical model

[Cabbage.jl](https://github.com/cropbox/Cabbage.jl) is a Cropbox port of the
pycabbage model.

This repository is retained because it documents how Cropbox has been used,
but its code may target an older Cropbox or Julia release. Check its project
files before reusing an example in a new environment.

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
