# Configuration

In Cropbox, `Config` is a configuration object structured as a nested dictionary or a hash table. It stores user-defined parameter values as a triplet of *system* - *variable* - *value*. Providing a configuration object with specific parameter values during instantiation of a system allows the user to insert or replace values for parameter variables within the system. 

For a variable to be eligible for adjustment through a configuration, the variable must have the `parameter` tag. There are six possible variable states that have access to the `parameter` tag: [`preserve`](@ref preserve), [`flag`](@ref flag), [`provide`](@ref provide), [`drive`](@ref drive), [`tabulate`](@ref tabulate), and [`interpolate`](@ref interpolate). The type of *value* that you assign in a configuration will vary depending on the variable state. For example, a configuration for a `flag` variable will contain an expression that can be evaluated as `true` or `false`.

## Creating a Configuration

Configurations are created using the `@config` macro.

```@setup Cropbox
using Cropbox
using DataFrames
```

**Example**

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve(parameter)
end

config = @config(:S => :a => 2)

instance(S; config)
```

When the system is defined, the variable `a` is a `preserve` variable with the value of `1`. Because the variable has a `parameter` tag, its value can be assigned with a configuration at instantiation.

A configuration can be used to change the value of *any* parameter variable within the system. This includes parameters variables within built-in systems such as `Clock` and `Calendar`. 

## Changing the Time Step

By default, a model simulation in Cropbox updates at an hourly interval. Based on your model, there may be times when you want to change the time step of the simulation. This too can be done using a configuration. In order to change the time step value, all we need is to assign a new value for `step`, which is simply a `preserve` variable with the `parameter` tag in the `Clock` system.

**Example**

Here we create a simple system with an `advance` variable that simply starts at 0 and increases by 1.

```@example Cropbox
@system S(Controller) begin
    a ~ advance
end

simulate(S; stop=5u"hr")
```

Configuring the `step` variable within the `Clock` system allows us to change the simulation to a daily interval.

```@example Cropbox
c = @config(:Clock => :step => 1u"d")

simulate(S; config=c, stop=5u"d")
```

## Supplying a DataFrame to a `provide` Variable

Apart from changing numerical parameter values, configurations are also commonly used to provide a new DataFrame to a `provide` variable that stores data for simulation. The syntax of the configuration remains identical, but instead of a numerical value, we provide a DataFrame. This allows us to easily run multiple simulations of a model using different datasets.

**Example**

```@example Cropbox
@system S(Controller) begin
    D ~ provide
end

config = @config(
    :S => :D => DataFrame(index=(0:3)u"hr", value=0:10:30)
)
```