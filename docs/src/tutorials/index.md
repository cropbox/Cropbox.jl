# [Learning Path](@id learning-path)

Start with the [Quick Start](@ref quick-start). It takes one model from a
declaration to a simulation, a graph, and a comparison between scenarios.
The three core-concept pages explain that workflow without requiring you to
learn every declaration form or function option first.

## Build a model, one step at a time

Follow these tutorials in order. Each is self-contained: run its code blocks
from the top, even if you have already run another tutorial.

| Tutorial | New idea | Result to read |
|---|---|---|
| [Logistic Growth](@ref logistic-growth-tutorial) | Turn a growth equation into a rate and an accumulated state. | A biomass trajectory approaching its final size. |
| [Weather-driven Phenology](@ref phenology-tutorial) | Supply dated weather data and accumulate thermal time. | Development under changing temperature. |
| [Predator–Prey Model](@ref lotka-volterra-tutorial) | Couple two changing states and extend a model with a mixin. | The interaction between prey and predator populations. |

After these tutorials, use [Configure Models and Scenarios](@ref
configuration-workflow) to organize experiments, or [Evaluate and Calibrate
Models](@ref evaluation-tutorial) when observations are available.

## Choose a model study

The remaining tutorials are applications, not prerequisites for using Cropbox.
Choose one that matches your work:

- [Leaf Gas Exchange](@ref leaf-gas-exchange-tutorial): environmental responses
  in a coupled leaf model.
- [Garlic Growth Model](@ref garlic-tutorial): whole-plant growth and dynamic
  organs.
- [SimpleCrop](@ref simplecrop-tutorial): development, canopy growth, and
  biomass partitioning in a compact crop model.
- [Soil Water Transport](@ref soil-water-transport-tutorial): hydraulic
  properties and water movement through a layered profile.
- [Root System Architecture](@ref croprootbox-tutorial): growing geometry,
  stochastic parameters, and custom summaries.

[Models and Resources](@ref Gallery) collects the model repositories, talks,
and workshop notebooks. Each study explains its inputs and links the relevant
publications.

## Look up details when needed

The [Reference](@ref reference-guide) is a dictionary, not the next lesson.
Follow a link from an example when you need the exact syntax, all supported
arguments, return values, or additional plotting forms. You do not need to read
it from beginning to end before running a model.
