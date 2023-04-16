```@setup Cropbox
using Cropbox
using DataFrames
```

# [Configuration](@id Configuration1)

In Cropbox, `Config` is a configuration object structured as a nested dictionary or a hash table. It stores user-defined parameter values as a triplet of *system* - *variable* - *value*. Providing a configuration object with specific parameter values during instantiation of a system allows the user to insert or replace values for parameter variables within the system. 

For a variable to be eligible for adjustment through a configuration, the variable must have the `parameter` tag. There are six possible variable states that have access to the `parameter` tag: [`preserve`](@ref preserve), [`flag`](@ref flag), [`provide`](@ref provide), [`drive`](@ref drive), [`tabulate`](@ref tabulate), and [`interpolate`](@ref interpolate). The type of *value* that you assign in a configuration will vary depending on the variable state. For example, a configuration for a `flag` variable will contain an expression that can be evaluated as `true` or `false`.

## Creating a Configuration

Configurations are created using the `@config` macro. 

A basic unit of configuration for a system `S` is represented as a pair in the form of `S => p` (`p` represents a parameter). The parameter variable and its corresponding value is represented as another pair in the form of `p => v`. In other words, a configuration is created by pairing system `S` to a pairing of parameter variable and value `p => v`, like so: `:S => :p => v`.

**Example**

Here is an example of changing the value of a parameter variable using a configuration.

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve(parameter)
    b => 2 ~ preserve(parameter)
end

config = @config(:S => :a => 2)

instance(S; config)
```

In system `S`, the variable `a` is a `preserve` variable with the value of `1`. Because the variable has the `parameter` tag, its value can be reassigned with a configuration at instantiation.

!!! note "Note"
    A configuration can be used to change the value of *any* parameter variable within a system. This includes parameters variables within built-in systems such as `Clock` and `Calendar`.

### Syntax

The `@config` macro accepts a number of different syntaxes to create a configuration object.

Below is an example of creating the most basic configuration. Note that the system `S` is written as a [symbol](https://docs.julialang.org/en/v1/base/base/#Core.Symbol).

```@example Cropbox
@config :S => :a => 2
```

!!! note "Note"
    When creating a configuration for a system, the system name is expressed as a symbol in the form of `:S`. If the actual system type is used in the form of `S`, its name will automatically be converted into a symbol.

#### Multiple Parameters

When specifying multiple parameters in a system, we can pair the system to either a tuple of pairs or named tuples.

**Tuple of Pairs**
```@example Cropbox
@config :S => (:a => 1, :b => 2)
```

**Named Tuples**
```@example Cropbox
@config :S => (a = 1, b = 2)
```

#### Multiple Systems

We can create configurations for multiple systems by concatenating the configuration for each system into a tuple. For multiple parameters in multiple systems, you can use either a tuple of pairs or named tuples, as shown previously.

```@example Cropbox
@system S1 begin
    a ~ preserve
end

@system S2 begin
    b ~ preserve
end

@config(:S1 => :a => 1, :S2 => :b => 2)
```

#### Multiple Configurations

When multiple sets of configurations are needed, as in the `configs` argument for `simulate()`, a vector of `Config` objects is used. 

```@example Cropbox
c = @config[:S => :a => 1, :S => :a => 2]
```

The `@config` macro also supports some convenient ways to construct a vector of configurations. 

The prefix operator `!` allows `expansion` of any iterable placed in the configuration value. For example, `!(:S => :a => 1:2)` is expanded into two sets of separate configurations [:S => :a => 1, :S => :a => 2].

```@example Cropbox
@config !(:S => :a => 1:2)
```

The infix operator `*` allows multiplication of a vector of configurations with another vector or a single configuration to construct multiple sets of configurations. For example, `(:S => :a => 1:2) * (:S => :b => 0)` is multiplied into [:S => (a = 1, b = 0), :S => (a = 2, b = 0)].

```@example Cropbox
@config (:S => :a => 1:2) * (:S => :b => 0)
```

#### Combining Configurations

When you have multiple `Config` objects that you want to combine without making one from scratch, you can do that also using the `@config` macro. If there are variables with identical names, note that the value from the latter configuration will take precedence.

```@example Cropbox
c1 = :S => (:a => 1, :b => 1)
c2 = :S => (:b => 2)

c3 = @config(c1, c2)
```

## Changing the Time Step

By default, a model simulation in Cropbox updates at an hourly interval. Based on your model, there may be times when you want to change the time step of the simulation. This can be done using a configuration. In order to change the time step value, all we need to do is assign a new value for `step`, which is simply a `preserve` variable with the `parameter` tag in the `Clock` system.

**Example**

Here we create a simple system with an `advance` variable that simply starts at 0 and increases by 1 every time step (the variable is irrelevant).

```@example Cropbox
@system S(Controller) begin
    a ~ advance
end

simulate(S; stop=2u"hr")
```
\

We can configure the `step` variable within the `Clock` system to `1u"d"`, then insert the configuration object into the `simulate()` function, changing the simulation to a daily interval.

```@example Cropbox
c = @config(:Clock => :step => 1u"d")

simulate(S; config=c, stop=2u"d")
```

## Supplying a DataFrame to a `provide` Variable

Apart from changing numerical parameter values, configurations are also commonly used to provide a new DataFrame to a `provide` variable that stores data for simulation. The syntax of the configuration remains identical, but instead of a numerical value, we provide a DataFrame. This allows us to easily run multiple simulations of a model using different datasets.

**Example**

```@example Cropbox
@system S(Controller) begin
    D ~ provide(parameter)
end

c = @config(
    :S => :D => DataFrame(index=(0:2)u"hr", value=0:10:20)
)

instance(S; config=c)
```