```@setup Cropbox
using Cropbox
using CSV
using DataFrames
using DataFramesMeta
using Dates
using TimeZones

pelts = DataFrame(
    "Year (yr)" => [1845, 1846, 1847, 1848, 1849, 1850, 1851, 1852, 1853, 1854, 1855, 1856, 1857, 1858, 1859, 1860, 1861, 1862, 1863, 1864, 1865, 1866, 1867, 1868, 1869, 1870, 1871, 1872, 1873, 1874, 1875, 1876, 1877, 1878, 1879, 1880, 1881, 1882, 1883, 1884, 1885, 1886, 1887, 1888, 1889, 1890, 1891, 1892, 1893, 1894, 1895, 1896, 1897, 1898, 1899, 1900, 1901, 1902, 1903, 1904, 1905, 1906, 1907, 1908, 1909, 1910, 1911, 1912, 1913, 1914, 1915, 1916, 1917, 1918, 1919, 1920, 1921, 1922, 1923, 1924, 1925, 1926, 1927, 1928, 1929, 1930, 1931, 1932, 1933, 1934, 1935],
    "Hare" => [19.58, 19.6, 19.61, 11.99, 28.04, 58.0, 74.6, 75.09, 88.48, 61.28, 74.67, 88.06, 68.51, 32.19, 12.64, 21.49, 30.35, 2.18, 152.65, 148.36, 85.81, 41.41, 14.75, 2.28, 5.91, 9.95, 10.44, 70.64, 50.12, 50.13, 101.25, 97.12, 86.51, 72.17, 38.32, 10.11, 7.74, 9.67, 43.12, 52.21, 134.85, 134.86, 103.79, 46.1, 15.03, 24.2, 41.65, 52.34, 53.78, 70.4, 85.81, 56.69, 16.59, 6.16, 2.3, 12.82, 4.72, 4.73, 37.22, 69.72, 57.78, 28.68, 23.37, 21.54, 26.34, 53.1, 68.48, 75.58, 57.92, 40.97, 24.95, 12.59, 4.97, 4.5, 11.21, 56.6, 69.63, 77.74, 80.53, 73.38, 36.93, 4.64, 2.54, 1.8, 2.39, 4.23, 19.52, 82.11, 89.76, 81.66, 15.76],
    "Lynx" => [30.09, 45.15, 49.15, 39.52, 21.23, 8.42, 5.56, 5.08, 10.17, 19.6, 32.91, 34.38, 29.59, 21.3, 13.69, 7.65, 4.08, 4.09, 14.33, 38.22, 60.78, 70.77, 72.77, 42.68, 16.39, 9.83, 5.8, 5.26, 18.91, 30.95, 31.18, 46.34, 45.77, 44.15, 36.33, 12.03, 12.6, 18.34, 35.14, 43.77, 65.69, 79.35, 51.65, 32.59, 22.45, 16.16, 14.12, 20.38, 33.33, 46.0, 51.41, 46.43, 33.68, 18.01, 8.86, 7.13, 9.47, 14.86, 31.47, 60.57, 63.51, 54.7, 6.3, 3.41, 5.44, 11.65, 20.35, 32.88, 39.55, 43.36, 40.83, 30.36, 17.18, 6.82, 3.19, 3.52, 9.94, 20.3, 31.99, 42.36, 49.08, 53.99, 52.25, 37.7, 19.14, 6.98, 8.31, 16.01, 24.82, 29.7, 35.4]
)
```
# Lotka-Volterra Equations

In this tutorial, we will create a model that simulates population dynamics between prey and predator using the Lotka-Volterra equations. The Lotka-Volterra equations are as follows:

```math
\begin{align}
\frac{dN}{dt} &= bN - aNP \\
\frac{dP}{dt} &= caNP - mP \\
\end{align}
```
\

Here is a list of variables used in the system:

| Symbol | Value | Units | Description |
| :---: | :---: | :---: | :--- |
| t | - | $\mathrm{yr}$ | Time unit used in the model |
| N | - | - | Prey population as number of individuals (state variable) |
| P | - | - | Predator population as number of individuals (state variable) |
| b | - | $\mathrm{yr^{-1}}$ | Per capital birth rate that defines the intrinsic growth rate of prey population |
| a | - | $\mathrm{yr^{-1}}$ | Attack rate or predation rate |
| c | - | - | Conversion efficiency of an eaten prey into new predator; predator's reproduction efficiency per prey consumed) |
| m | - | $\mathrm{yr^{-1}}$ | Mortality rate of predator population |
\

Let's begin by creating a [system](@ref System) called `LotkaVolterra`. Since this is a system that we want to simulate later on, we must include [`Controller`](@ref Controller) as a [mixin](@ref Mixin).

```
@system LotkaVolterra(Controller)
```
\

We will first declare a time variable with a yearly unit, which we will use for plotting the model simulations later on. Recall that `context.clock.time` is a variable that keeps track of the progression of time. We are simply declaring a variable to keep track of the time in years.

```
@system LotkaVolterra(Controller) begin
    t(context.clock.time) ~ track(u"yr")
end
```
\

Next, we will declare the parameters in the equations as `preserve` variables. `preserve` variables are variables that remain constant throughout a simulation.

```
@system LotkaVolterra(Controller) begin
    t(context.clock.time) ~ track(u"yr")

    b: prey_birth_rate            ~ preserve(parameter, u"yr^-1")
    a: predation_rate             ~ preserve(parameter, u"yr^-1")
    c: predator_reproduction_rate ~ preserve(parameter)
    m: predator_mortality_rate    ~ preserve(parameter, u"yr^-1")
end
```
\

Now let's declare the prey and predator populations as variables. The Lotka-Volterra equations describe the rates of change for the two populations. As we want to track the actual number of the two populations, we will declare the two populations as `accumulate` variables, which are simply Euler integrations of the two population rates. Note that a variable can be used as its own depending variable.

```
@system LotkaVolterra(Controller) begin
    t(context.clock.time) ~ track(u"yr")

    b: prey_birth_rate            ~ preserve(parameter, u"yr^-1")
    a: predation_rate             ~ preserve(parameter, u"yr^-1")
    c: predator_reproduction_rate ~ preserve(parameter)
    m: predator_mortality_rate    ~ preserve(parameter, u"yr^-1")

    N(N, P, b, a):    prey_population     =>     b*N - a*N*P ~ accumulate
    P(N, P, c, a, m): predator_population => c*a*N*P -   m*P ~ accumulate
end
```
\

By default, `accumulate` variables initialize at a value of zero. In our current model, that would result in two populations remaining at zero indefinitely. To address this, we will define the initial values for the two `accumulate` variables using the `init` tag. We can specify a particular value, or we can also create and reference new parameters representing the two initial populations. We will go with the latter option as it allows us to flexibly change the initial populations with a configuration.

```@example Cropbox
@system LotkaVolterra(Controller) begin
    t(context.clock.time) ~ track(u"yr")

    b: prey_birth_rate            ~ preserve(parameter, u"yr^-1")
    a: predation_rate             ~ preserve(parameter, u"yr^-1")
    c: predator_reproduction_rate ~ preserve(parameter)
    m: predator_mortality_rate    ~ preserve(parameter, u"yr^-1")

    N0: prey_initial_population     ~ preserve(parameter)
    P0: predator_initial_population ~ preserve(parameter)

    N(N, P, b, a):    prey_population     =>     b*N - a*N*P ~ accumulate(init=N0)
    P(N, P, c, a, m): predator_population => c*a*N*P -   m*P ~ accumulate(init=P0)
end
```
\

**Configuration**

With the system now defined, we will create a `Config` object to fill or adjust the parameters.

First, we will change the `step` variable in the `Clock` system to `1u"d"`, which will make the system update at a daily interval. Recall that `Clock` is a system that is referenced in all systems by default. You can technically run the model with any timestep.

```@example Cropbox
lvc = @config (:Clock => :step => 1u"d")
```
\

Next, we will configure the parameters in the `LotkaVolterra` system that we defined. Note that we can easily combine configurations by providing multiple elements.

```@example Cropbox
lvc = @config (lvc,
    :LotkaVolterra => (
        b = 0.6,
        a = 0.02,
        c = 0.5,
        m = 0.5,
        N0 = 20,
        P0 = 30
    )
)
```
\

**Visualization**

Let's visualize the `LotkaVolterra` system with the configuration that we just created, using the `visualize()` function. The `visualize()` function both runs a simulation and plots the resulting DataFrame.

```@example Cropbox
visualize(LotkaVolterra, :t, [:N, :P]; config = lvc, stop = 100u"yr", kind = :line)
```
\

### Density-Dependent Lotka-Volterra Equations

Now let's try to make a density-dependent version of the original Lotka-Volterra model which incorporates a new term in the prey population rate. The new variable *K* represents the carrying capacity of the prey population.

```math
\begin{align}
\frac{dN}{dt} &= bN-\frac{b}{K}N^2-aNP \\
\frac{dP}{dt} &= caNP-mP \\
\end{align}
```

We will call this new system `LotkaVolterraDD`.

```
@system LotkaVolterraDD(Controller)
```
\

Since we already defined the `LotkaVolterra` system, which already has most of the variables we require, we can use `LotkaVolterra` as a mixin for `LotkaVolterraDD`. This makes our task a lot simpler, as all that remains is to declare the variable `K` for carrying capacity and redeclare the variable `N` for prey population. The variable `N` in the new system will automatically overwrite the `N` from `LotkaVolterra`. 

```@example Cropbox
@system LotkaVolterraDD(LotkaVolterra, Controller) begin
    N(N, P, K, b, a): prey_population => begin
        b*N - b/K*N^2 - a*N*P
    end ~ accumulate(init = N0)
    
    K: carrying_capacity ~ preserve(parameter)
end
```
\

**Configuration**

Much like the new system, the new configuration can be created by reusing the old configuration. All we need to do is configure the new variable `K`.

```@example Cropbox
lvddc = @config(lvc, (:LotkaVolterraDD => :K => 1000))
```
\

**Visualization**

Once again, let's visualize the system using the `visualize()` function.

```@example Cropbox
visualize(LotkaVolterraDD, :t, [:N, :P]; config = lvddc, stop = 100u"yr", kind = :line)
```
\

### Calibration

If you want to calibrate the parameters according to a particular dataset, Cropbox provides the `calibrate()` function, which relies on [BlackBoxOptim.jl](https://github.com/robertfeldt/BlackBoxOptim.jl) for global optimization methods. If you are interested in local optimization methods, refer to [Optim.jl](https://github.com/JuliaNLSolvers/Optim.jl) package for more information.

For this tutorial, we will use a dataset containing the number of pelts (in thousands) of Canadian lynx and snowshoe hare traded by the Hudson Bay Trading Company in Canada from 1845 to 1935.

```@example Cropbox
first(pelts, 3)
```
\

Recall that we can use the `unitfy()` function in Cropbox to automatically assign units when they are specified in the column headers.

```@example Cropbox
pelts = unitfy(pelts)
first(pelts, 3)
```
\

Let's plot the data and see what it looks like.

```@example Cropbox
visualize(pelts, :Year, [:Hare, :Lynx], kind = :scatterline)
```
\

For our calibration, we will use a subset of the data covering years 1900 to 1920.

```@example Cropbox
pelts_subset = @subset(pelts, 1900u"yr" .<= :Year .<= 1920u"yr")
```
\

Before we calibrate the parameters for `LotkaVolterra`, let's add one new variable to the system. We will name this variable `y` for year. The purpose of `y` is to keep track of the year in the same manner as the dataset.

```@example Cropbox
@system LotkaVolterra(Controller) begin
    t(context.clock.time) ~ track(u"yr")
    y(t): year            ~ track::Int(u"yr", round)

    b: prey_birth_rate            ~ preserve(parameter, u"yr^-1")
    a: predation_rate             ~ preserve(parameter, u"yr^-1")
    c: predator_reproduction_rate ~ preserve(parameter)
    m: predator_mortality_rate    ~ preserve(parameter, u"yr^-1")

    N0: prey_initial_population     ~ preserve(parameter)
    P0: predator_initial_population ~ preserve(parameter)

    N(N, P, b, a):    prey_population     =>     b*N - a*N*P ~ accumulate(init=N0)
    P(N, P, c, a, m): predator_population => c*a*N*P -   m*P ~ accumulate(init=P0)
end
```
\

We will now use the `calibrate()` function to find parameters that fit the data. Keep in mind that the search range for each parameter will be determined by you. We will use the `snap` option to explicitly indicate that the output should be recorded by 365-day intervals to avoid excessive rows in the DataFrame causing unnecessary slowdown. Note that we will use `365u"d"` instead of `1u"yr"` which is technically equivalent to `365.25u"d"` following the convention in astronomy. For information regarding syntax, please check the [reference](@ref Simulation1).

```@example Cropbox
lvcc = calibrate(LotkaVolterra, pelts_subset;
    index = :Year => :y,
    target = [:Hare => :N, :Lynx => :P],
    config = :Clock => (:init => 1900u"yr", :step => 1u"d"),
    parameters = LotkaVolterra => (;
        b = (0, 2),
        a = (0, 2),
        c = (0, 2),
        m = (0, 2),
        N0 = (0, 100),
        P0 = (0, 100),
    ),
    stop = 20u"yr",
    snap = 365u"d"
)
```
\

As you can see above, the `calibrate()` function will return a `Config` object for the system.

Using the new configuration, let's make a comparison plot to visualize how well the simualation with the new parameters fits the data.

```@example Cropbox
p1 = visualize(pelts_subset, :Year, [:Hare, :Lynx]; kind = :scatterline)
visualize!(p1, LotkaVolterra, :t, [:N, :P];
    config = (lvcc, :Clock => (:init => 1900u"yr", :step => 1u"d")),
    stop = 20u"yr",
    kind = :line,
    colors = [1, 2],
    names = [],
)
```
\

Now let's try calibrating the density-dependent version of the model. Since we made a slight change to `LotkaVolterra`, let's make sure to define `LotkaVolterraDD` again.

```@example Cropbox
@system LotkaVolterraDD(LotkaVolterra, Controller) begin
    N(N, P, K, b, a): prey_population => begin
        b*N - b/K*N^2 - a*N*P
    end ~ accumulate(init = N0)
    
    K: carrying_capacity ~ preserve(parameter)
end
```
```@setup Cropbox
@system LotkaVolterraDD(Controller) begin
    t(context.clock.time) ~ track(u"yr")
    y(t): year            ~ track::Int(u"yr", round)

    b: prey_birth_rate            ~ preserve(parameter, u"yr^-1")
    a: predation_rate             ~ preserve(parameter, u"yr^-1")
    c: predator_reproduction_rate ~ preserve(parameter)
    m: predator_mortality_rate    ~ preserve(parameter, u"yr^-1")
    K: carrying_capacity          ~ preserve(parameter)

    N0: prey_initial_population     ~ preserve(parameter)
    P0: predator_initial_population ~ preserve(parameter)

    N(N, P, b, a, K): prey_population     => b*N - b/K*N^2 - a*N*P ~ accumulate(init=N0)
    P(N, P, c, a, m): predator_population =>       c*a*N*P -   m*P ~ accumulate(init=P0)
end
```
\

Don't forget to add `K` among the parameters that we want to calibrate.

```@example Cropbox
lvddcc = calibrate(LotkaVolterraDD, pelts_subset;
    index = :Year => :y,
    target = [:Hare => :N, :Lynx => :P],
    config = :Clock => (:init => 1900u"yr", :step => 1u"d"),
    parameters = LotkaVolterraDD => (;
        b = (0, 2),
        a = (0, 2),
        c = (0, 2),
        m = (0, 2),
        N0 = (0, 100),
        P0 = (0, 100),
        K = (0, 1000)
    ),
    stop = 20u"yr",
    snap = 365u"d"
)
```
\

Once again, let us make a comparison plot to see how the density-dependent version of the model fares against the original dataset.

```@example Cropbox
p2 = visualize(pelts_subset, :Year, [:Hare, :Lynx]; kind = :scatterline)
visualize!(p2, LotkaVolterraDD, :t, [:N, :P];
    config = (lvddcc, :Clock => (:init => 1900u"yr", :step => 1u"d")),
    stop = 20u"yr",
    kind = :line,
    colors = [1, 2],
    names = [],
)
```
\

**Evaluation**

We have visualized how the simulated `LotkaVolterra` and `LotkaVolterraDD` systems compare to the the original dataset. Let us obtain a metric for how well the simulations fit the original dataset using the `evaluate()` function in Cropbox. The `evaluate()` function supports numerous different metrics for evaluation. Here, we will calculate the root-mean-square error (RMSE) and modeling efficiency (EF).

Here are the evaluation metrics for `LotkaVolterra`. The numbers in the tuples correspond to hare and lynx, respectively.

```@example Cropbox
evaluate(LotkaVolterra, pelts_subset;
    index = :Year => :y,
    target = [:Hare => :N, :Lynx => :P],
    config = (lvcc, :Clock => (:init => 1900u"yr", :step => 1u"d")),
    stop = 20u"yr",
    snap = 365u"d",
    metric = :rmse,
)
```
```@example Cropbox
evaluate(LotkaVolterra, pelts_subset;
    index = :Year => :y,
    target = [:Hare => :N, :Lynx => :P],
    config = (lvcc, :Clock => (:init => 1900u"yr", :step => 1u"d")),
    stop = 20u"yr",
    snap = 365u"d",
    metric = :ef
)
```
\

Here are the evaluation metrics for `LotkaVolterraDD`:

```@example Cropbox
evaluate(LotkaVolterraDD, pelts_subset;
    index = :Year => :y,
    target = [:Hare => :N, :Lynx => :P],
    config = (lvddcc, :Clock => (:init => 1900u"yr", :step => 1u"d")),
    stop = 20u"yr",
    snap = 365u"d",
    metric = :rmse
)
```
```@example Cropbox
evaluate(LotkaVolterraDD, pelts_subset;
    index = :Year => :y,
    target = [:Hare => :N, :Lynx => :P],
    config = (lvddcc, :Clock => (:init => 1900u"yr", :step => 1u"d")),
    stop = 20u"yr",
    snap = 365u"d",
    metric = :ef
)
```