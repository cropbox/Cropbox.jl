!!! warning "Warning"
    This page is incomplete. Please check the Reference page for information regarding functions.

# Simulation

There are four different simulative functions in Cropbox that we can run with a model.

```@contents
Pages = ["simulation.md"]
```

!!! tip "Tip"
    When running any simulative function, do not forget to include `Controller` as one of the mixins for the system that you which to simulate.

## `instance()`

```
instance(S; <keyword arguments>) -> S
```

The instance function makes an instance of a system `S` with an initial condition specified by configuration and additional options.

### Keyword Arguments

`config=()`

`options=()`

`seed=nothing`

## `simulate()`

`simulate()` runs a simulation by creating an instance of a specified system and updating it a specified number of times in order to generate an output in the form of a DataFrame.

```
simulate([f,] S[, layout, [configs]]; <keyword arguments>) -> DataFrame
```

### Arguments

`S::Type{<:System}`

`layout::Vector`

`configs::Vector`

### Keyword Arguments

#### Layout

`base=nothing`

`index=nothing`

`target=nothing`

`meta=nothing`

#### Configuration

`config=()`

`configs=[]`

`seed=nothing`

#### Progress

`stop=nothing`

`snap=nothing`

`snatch=nothing`

`verbose=true

#### Format

`nounit=false`

`long=false`

## `evaluate()`

```
evaluate(S, obs; <keyword arguments>) -> Number | Tuple
```

## `calibrate()`

```
calibrate(S, obs; <keyword arguments>) -> Config | OrderedDict
```

Cropbox includes a calibrate() function that helps determine parameter values based on a provided dataset. Internally, this process relies on [BlackBoxOptim.jl](https://github.com/robertfeldt/BlackBoxOptim.jl) for global optimization methods.

The `calibrate()` function returns a Config object that we can directly use in model simulations. 