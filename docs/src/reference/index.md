# [Public API Index](@id public-api-index)

This is a task-oriented index of supported names exported by Cropbox.
Deprecated compatibility aliases are intentionally omitted. “Advanced” means
that ordinary crop-model scripts rarely need the name, not that it is private.

## Modeling and configuration

| Name | Role | Reference |
|---|---|---|
| `@system` | declare a system type | [Declarations and Configuration](@ref declaration-api) |
| `System` | common abstract system type | [System](@ref system) |
| `@config`, `Config` | build and store configuration | [Declarations and Configuration](@ref declaration-api) |
| `parameters` | list configurable values | [Inspection](@ref Inspection1) |
| `Controller` | make a composed system executable | [Systems and Composition](@ref system) |
| `Context` | carry configuration and shared runtime state | [Model Execution](@ref model-execution) |
| `Clock`, `Calendar` | elapsed and civil time | [Model Execution](@ref model-execution) |
| `instance` | construct and initialize a system | [Simulation](@ref Simulation1) |
| `update!` | perform one manual update | [Simulation](@ref manual-update) |

## Simulation, analysis, and visualization

| Name | Role | Reference |
|---|---|---|
| `simulate`, `simulate!` | run fresh or existing systems | [Simulation](@ref Simulation1) |
| `evaluate` | compare observations and estimates | [Simulation](@ref Simulation1) |
| `calibrate` | search parameter bounds | [Simulation](@ref Simulation1) |
| `visualize`, `visualize!` | visualize existing data or simulation results | [Visualization](@ref Visualization1) |
| `manipulate` | add interactive parameter widgets | [Visualization](@ref Visualization1) |
| `look`, `@look`, `dive` | inspect declarations and instances | [Inspection](@ref Inspection1) |

## Values, units, and equations

| Name | Role | Reference |
|---|---|---|
| `value` | unwrap a state or supported wrapper | [Values and Units](@ref utility-api) |
| `nounit` | pass a state magnitude without its unit | [Values and Units](@ref utility-api) |
| `unitfy`, `deunitfy` | attach, convert, strip, or parse units | [Values and Units](@ref utility-api) |
| `u"..."` | Unitful unit string macro | [Built-in Model Components](@ref built-in-components) |
| `±` | Normal sampling specification | [Configure Models and Scenarios](@ref stochastic-configuration) |
| `⩵` | residual equality for solver behaviors | [Behaviors and Tags](@ref residual-equality) |
| `wrap` | pass a state object as a dependency (advanced) | [Behaviors and Tags](@ref behavior-wrap) |

## Dynamic structures

| Name | Role | Reference |
|---|---|---|
| `produce` | request dynamic child construction | [Dynamic Hierarchies](@ref dynamic-hierarchies) |
| `Gather` | traversal state and output store | [Dynamic Hierarchies](@ref dynamic-hierarchies) |
| `gather!`, `visit!` | dispatch and walk a model hierarchy | [Dynamic Hierarchies](@ref dynamic-hierarchies) |

## Reusable systems and re-exports

| Name | Role | Reference |
|---|---|---|
| `GrowingDegree` | threshold temperature response | [Built-in Model Components](@ref built-in-components) |
| `BetaFunction` | asymmetric normalized temperature response | [Built-in Model Components](@ref built-in-components) |
| `Q10Function` | Q10 temperature multiplier | [Built-in Model Components](@ref built-in-components) |
| `DataFrameStore`, `DayStore`, `DateStore`, `TimeStore`, `TableStore` | indexed tabular inputs | [Built-in Model Components](@ref built-in-components) |
| `Date`, `Dates` | re-exported Dates names | [Built-in Model Components](@ref built-in-components) |
| `ZonedDateTime`, `tz"..."` | re-exported TimeZones names | [Built-in Model Components](@ref built-in-components) |

## Documented object index

The generated index below links docstrings included in the reference pages.
Some exported helpers are described manually above because their implementation
does not yet carry a standalone docstring.

```@index
```
