# [How to Use the Reference](@id reference-guide)

These pages describe Cropbox in detail. Use them to answer a specific question
while writing or inspecting a model; they are not a sequence of lessons.
For a guided introduction, start with the [Quick Start](@ref quick-start) and
the [Learning Path](@ref learning-path).

## Find the right entry

| Question | Reference |
|---|---|
| How do I read or write a declaration? | [DSL Syntax](@ref dsl-syntax) |
| What does a behavior do, and which tags can it use? | [Behaviors and Tags](@ref behaviors-and-tags) |
| How are systems and configurations declared? | [Declarations and Configuration](@ref declaration-api) |
| How do construction, simulation, evaluation, and calibration work? | [Simulation API](@ref Simulation1) |
| How do sensitivity methods, bounds, and returned results differ? | [Sensitivity Analysis API](@ref sensitivity-analysis) |
| Which plotting call matches my data and intended comparison? | [Visualization API](@ref Visualization1) |
| How can I inspect parameters, declarations, and model structure? | [Inspection API](@ref Inspection1) |
| How do I read values or convert units? | [Values and Units](@ref utility-api) |
| How do I traverse a model with growing child systems? | [Dynamic Hierarchies](@ref dynamic-hierarchies) |
| Which ready-made components can I reuse? | [Built-in Model Components](@ref built-in-components) |

The [Public API Index](@ref public-api-index) provides an alphabetical docstring
index as well as a task-oriented list of exported names.

## Read an example with its contract

Reference entries include argument combinations, options, executable examples,
their output, and the conditions needed to interpret them correctly. For
example, the visualization reference pairs graphical results with expandable
terminal output rather than asking you to infer a plot from its call signature.

Code blocks in the same page can share setup. Run them in page order when an
example refers to a model or table defined earlier. A signature containing
`options...` is a description of the call, not a complete runnable example.
