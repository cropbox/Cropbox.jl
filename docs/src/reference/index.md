# [Public API Index](@id public-api-index)

This is a task-oriented index of names exported by Cropbox. “Advanced” means
that ordinary crop-model scripts rarely need the name, not that it is private.

## Modeling and configuration

| Name | Role | Reference |
|---|---|---|
| `@system` | declare a system type | [Declarations and Configuration](@ref declaration-api) |
| `System` | common abstract system type | [System](@ref system) |
| `@config`, `Config` | build and store configuration | [Declarations and Configuration](@ref declaration-api) |
| `parameters` | list configurable values | [Inspection](@ref Inspection1) |
| `Controller`, `Context` | root construction and shared runtime context | [System](@ref system) |
| `Clock`, `Calendar` | elapsed and civil time | [System](@ref system) |
| `instance` | construct and initialize a system | [Simulation](@ref Simulation1) |
| `update!` | perform one manual update | [Values, Units, and Structure](@ref utility-api) |

## Simulation, analysis, and plotting

| Name | Role | Reference |
|---|---|---|
| `simulate`, `simulate!` | run fresh or existing systems | [Simulation](@ref Simulation1) |
| `evaluate` | compare observations and estimates | [Simulation](@ref Simulation1) |
| `calibrate` | search parameter bounds | [Simulation](@ref Simulation1) |
| `plot`, `plot!` | plot vectors and tables | [Visualization](@ref Visualization1) |
| `visualize`, `visualize!` | simulate and plot, or plot existing data | [Visualization](@ref Visualization1) |
| `manipulate` | add interactive parameter widgets | [Visualization](@ref Visualization1) |
| `look`, `@look`, `dive` | inspect declarations and instances | [Inspection](@ref Inspection1) |

## Values, units, and equations

| Name | Role | Reference |
|---|---|---|
| `value` | unwrap a state or supported wrapper | [Values, Units, and Structure](@ref utility-api) |
| `nounit` | pass a state magnitude without its unit | [Values, Units, and Structure](@ref utility-api) |
| `unitfy`, `deunitfy` | attach, convert, strip, or parse units | [Values, Units, and Structure](@ref utility-api) |
| `u"..."` | Unitful unit string macro | [Built-in Model Components](@ref built-in-components) |
| `±` | Normal sampling specification | [Values, Units, and Structure](@ref utility-api) |
| `⩵` | residual equality for solver behaviors | [Values, Units, and Structure](@ref utility-api) |
| `wrap` | pass a state object as a dependency (advanced) | [Values, Units, and Structure](@ref utility-api) |

## Dynamic structures

| Name | Role | Reference |
|---|---|---|
| `produce` | request dynamic child construction | [Values, Units, and Structure](@ref utility-api) |
| `Gather` | traversal state and output store | [Values, Units, and Structure](@ref utility-api) |
| `gather!`, `visit!` | dispatch and walk a model hierarchy | [Values, Units, and Structure](@ref utility-api) |

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
