```@setup Cropbox
using Cropbox
using DataFrames
```

# Simulation

There are four different functions in Cropbox for model simulation. For information regarding syntax, please check the [reference](@ref Simulation1).
* [`instance()`](@ref instance)
* [`simulate()`](@ref simulate)
* [`evaluate()`](@ref evaluate)
* [`calibrate()`](@ref calibrate)

!!! tip "Tip"
    When running any of these functions, do not forget to include `Controller` as a mixin for the system.

## [`instance()`](@id instance)

The `instance()` function is the core of all simulative functions. To run any kind of simulation of a system, the system must first be instantiated. The `instance()` function simply makes an instance of a system with an initial condition specified by a configuration and additional options.

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ advance
    b => 1 ~ preserve(parameter)
    c(a, b) => a*b ~ track
end

s = instance(S)
```

After creating an instance of a system, we can simulate the system manually, using the `update!()` function.

```@example Cropbox
update!(s)
```
```@example Cropbox
update!(s)
```

We can also specify a configuration object in the function to change or fill in parameter values of the system.

```@example Cropbox
c = @config(:S => :b => 2)

instance(S; config=c)
```

## [`simulate()`](@id simulate)

`simulate()` runs a simulation by creating an instance of a specified system and updating it a specified number of times in order to generate an output in the form of a DataFrame. You can think of it as a combination of the `instance()` and the `update!()` function where each row of the DataFrame represents an update.

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ advance
    b => 1 ~ preserve(parameter)
    c(a, b) => a*b ~ track
end

 simulate(S; stop=2)
```

Just like the `instance()` function, we can add a configuration object to change or fill in the parameter values.

```@example Cropbox
c = @config(:S => :b => 2)

simulate(S; config=c, stop=2)
```
\

!!! tip "Tip"
    When using the `simulate()` function, it is recommended to always include an argument for the `stop` keyword unless you only want to see the initial calculations.

## [`evaluate()`](@id evaluate)

The `evaluate()` function compares two datasets with a choice of evaluation metric. You can compare two DataFrames (commonly the observation and the estimation data), or a System and a DataFrame, which will automatically simulate the system to generate a DataFrame that can be compared. Naturally, if you already have a DataFrame output from a previous simulation, you can use the first method.

**Two DataFrames**
```@example Cropbox
obs = DataFrame(time = [1, 2, 3]u"hr", a = [10, 20, 30]u"g")

est = DataFrame(time = [1, 2, 3]u"hr", a = [11, 19, 31]u"g", b = [12, 22, 28]u"g")

evaluate(obs, est; index = :time, target = :a, metric = :rmse)
```

If the column names are different, you can pair the columns in the `target` argument to compare the two.

```@example Cropbox
evaluate(obs, est; index = :time, target = :a => :b)
```

**System and a DataFrame**
```@example Cropbox
@system S(Controller) begin
    p => 10 ~ preserve(parameter, u"g/hr")
    t(context.clock.time) ~ track(u"hr")
    a(p, t) => p*t ~ track(u"g")
end

evaluate(S, est; target = :a, stop = 3)
```

## [`calibrate()`](@id calibrate)

`calibrate()` is a function used to estimate a set of parameters for a given system, that will yield a simulation as closely as possible to a provided observation data. A multitude of simulations are conducted using different combinations of parameter values specified by a range of possible values. The optimal set of parameters is selected based on the chosen evaluation metric (RMSE by default). The algorithm used is the differential evolution algorithm from [BlackBoxOptim.jl](https://github.com/robertfeldt/BlackBoxOptim.jl. The function returns a Config object that we can directly use in model simulations.

**Example**

```@example Cropbox
@system S(Controller) begin
           a => 0 ~ preserve(parameter)
           b(a) ~ accumulate
end

obs = DataFrame(time=10u"hr", b=200)

p = calibrate(S, obs; target=:b, parameters=:S => :a => (0, 100), stop=10)
```