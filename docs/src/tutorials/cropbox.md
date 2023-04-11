```@setup Cropbox
using Cropbox
```

# [Getting Started with Cropbox](@id cropbox)

This tutorial will cover basic macros and functions of Cropbox.

## Installing Cropbox

[Cropbox.jl](https://github.com/cropbox/Cropbox.jl) is available through Julia package manager.

You can install Cropbox running the following command in the Julia REPL.

```julia
using Pkg
Pkg.add("Cropbox")
```

If you are using a prebuilt docker image with Cropbox included, you can skip this step.

## Package Loading

When using Cropbox, make sure to load the package into the environment by using the following command:

```@example Cropbox
using Cropbox
```

## Creating a System

In Cropbox, a model is defined by a single system or a collection of systems.

A system can be made by using a simple Cropbox macro, `@system`.

```@example Cropbox
@system S
```

We have just created a system called `S`. In its current state, `S` is an empty system with no variables. Our next step is to define the variables that will represent our system.

### Defining Variables

Suppose we want the system to represent exponential growth described by this differential equation

$\frac{dx}{dt} = ax$

In Cropbox, we could define the system with the following:
```@example Cropbox
@system S(Controller) begin
    i       => 1   ~ preserve
    a       => 0.1 ~ preserve(parameter)
    r(a, x) => a*x ~ track
    x(r)           ~ accumulate(init = i)
end
```
Here we declared four variables.

- i: variable containing initial value of x which never changes (preserved)
- a: variable containing constant parameter of exponential growth
- r: rate variable which needs to be calculated or tracked every time step
- x: state variable which accumulates by rate r over time with initial value i

Each variable has been declared with a state, such as preserve or track, that describes its behavior when the system is instantiated. In Cropbox, there are 19 different variable states, which are described in more detail in the [Variable section of the Manual](@ref variable). 

## Configuring Parameters
In modeling, we often need to change the value of a parameter for different systems or species. We can change the value of variables declared with the paramater tag before running the model by creating a config with the new value. For example, we could change the value of parameter a in system S to be .05 and then create an instance of S with this new value.  

```@example Cropbox
config = @config(:S => :a => .05)
instance(S; config)
```
Multiple parameters can be specified using tuples or named tuples. 
#### Tuple of Pairs
```@example Cropbox
@config :S => (:a => 1, :b => 2)
```
#### Named Tuples 
```@example Cropbox
@config :S => (a = 1, b = 2)
```
## Simulation
The simulate function will create an instance of the system and update the values of all the variables in it at each time step until it reaches the stop time. By default, simulations in Cropbox use a time step of one hour. 

Let's use Cropbox to simulate the system for ten time steps.
```@example Cropbox
df = simulate(S, config = config, stop = 10)
```
This will output the values of all the variables in the system as a DataFrame where each row represents one time step. 

## Visualization
Once we have simulated the system, we may want to visualize the resulting data by creating a graph. This can be done by using the plot() function, specifying the name of the dataframe as the first argument and then the names of variables we want to plot on the x and y axes. 
```@example Cropbox
p = plot(df, :time, :x)
```
The visualize() function can also be used to run a simulation and plot the results using one command. 
```@example Cropbox
v = visualize(S, :time, :x ; stop=50, kind=:line)
```

## Evaluation
The evaluate() function can be used to compare two datasets with a choice of evaluation metric, such as root-mean-square error. For instance, we could compare a dataset of the observed values from an experiment to the estimated values from a simulation. To do this, we would enter in the observed dataset as a DataFrame.

```@example Cropbox
using DataFrames
obs = DataFrame(time = [0.0 ,1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]u"hr", x = [1, .985, 1.06, 1.15, 1.14, 1.17, 1.24, 1.34, 1.76, 1.53, 1.68])
est = simulate(S, config = config, stop = 10)
```
We compare this dataset to the results of the simulation visually by adding it to the our previous plot `p` using the plot!() function. 
 
 ```@example Cropbox
plot!(p,obs, :time, :x)
```
Then, we can use the evaluate() function to calculate the error between the observed and simulated values. The index will be time by default and the target will be the variables we want to compare. 

```@example Cropbox
evaluate(obs, df; index = :time, target = :x, metric = :rmse)
```
In addition to being able to compare two DataFrames, the evaluate() function can also be used to compare a system to a DataFrame.

```@example Cropbox
evaluate(S, est; target = :a, stop = 10)
```

