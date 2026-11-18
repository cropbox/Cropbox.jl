# [Learning Path](@id learning-path)

Start with the [Quick Start](@ref quick-start). It takes one model from a
declaration to a simulation, a graph, and a comparison between scenarios.
Continue with Logistic Growth below. If you'd rather run a published crop model
before writing equations, start with the [Garlic Growth Model](@ref garlic-tutorial):
one growing season, from packaged weather to a graph of leaf and bulb dry mass.

## Build a model, one step at a time

Follow these tutorials in order. Each is self-contained: run its code blocks
from the top, even if you have already run another tutorial.

| Tutorial | New idea | Result to read |
|---|---|---|
| [Logistic Growth](@ref logistic-growth-tutorial) | Compare a simulated state with example measurements. | Observation points on the biomass curve and the root mean square error (RMSE). |
| [Weather-driven Phenology](@ref phenology-tutorial) | Supply dated weather data and accumulate thermal time. | Development under changing temperature. |
| [Predator–Prey Model](@ref lotka-volterra-tutorial) | Couple two changing states and extend a model with a mixin. | The interaction between prey and predator populations. |

After these tutorials, use [Configure Models and Scenarios](@ref
configuration-workflow) to organize experiments, or [Evaluate and Calibrate
Models](@ref evaluation-tutorial) when observations are available.

## Choose a model study

The remaining tutorials are applications, not prerequisites for using Cropbox.
Choose one that matches your work:

- [Garlic Growth Model](@ref garlic-tutorial): run a whole plant, then follow
  leaf development, compare planting dates, or examine individual organs.
- [Leaf Gas Exchange](@ref leaf-gas-exchange-tutorial): vary CO₂ or light and
  read the photosynthetic response of a leaf.
- [Root System Architecture](@ref croprootbox-tutorial): grow a maize root system,
  view its branching structure, and summarize root length by depth.
- [SimpleCrop](@ref simplecrop-tutorial): trace how weather, canopy growth, and
  biomass are connected in a small teaching model from the DSSAT materials.
- [Soil Water Transport](@ref soil-water-transport-tutorial): hydraulic
  properties and water movement through a layered profile.

[Models and Resources](@ref Gallery) collects the model repositories, talks,
and workshop notebooks. Each study explains its inputs and links the relevant
publications.

## Look up details when needed

The [Reference](@ref reference-guide) is a dictionary, not the next lesson.
Follow a link from an example when you need the exact syntax, all supported
arguments, return values, or additional plotting forms. You do not need to read
it from beginning to end before running a model.
