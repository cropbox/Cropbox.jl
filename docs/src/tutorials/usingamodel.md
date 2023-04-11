```@setup simple
```

# Using an Existing Cropbox Model

This tutorial will teach you how to use an existing Cropbox model. For this tutorial, we will be importing and utilizing a Cropbox model from a julia package called SimpleCrop.

## Installing a Cropbox Model

Often times, the Cropbox model that you want to use will be part of a Julia package.

If the package you want to install is under the official [Julia package registry](@https://github.com/JuliaRegistries/General), you can simply install the package using the following command.

```
using Pkg
Pkg.add("SimpleCrop")
```

You can also install any Julia package using a GitHub link.

```
using Pkg
Pkg.add("https://github.com/cropbox/SimpleCrop.jl")
```

## Importing a Cropbox Model

To start using a Julia package containing your desired model, you must first load the package into your environment.

This can be done by using this simple command.

```@example simple
using SimpleCrop
```

Let's not forget to load Cropbox as well.

```@example simple
using Cropbox
```

## Inspecting the Model

The model is implemented as a system named `Model` defined in SimpleCrop module. We can inspect the model with the `@look` macro, which will show us all the variables in the system.  

```@example simple
@look SimpleCrop.Model
```
@look can also be used to inspect individual state variables. 

```@example simple
@look SimpleCrop.Model.W
```
The relationship between the variables in the model can be visualized using a dependency graph. 

```@example simple
Cropbox.dependency(SimpleCrop.Model)
```
If an arrow points from one variable to a second variable, then the value of the second variable depends on, or is calculated with, the value of the first. 

We can view the values of all the parameters of the model with the following command.

```@example simple
parameters(SimpleCrop.Model; alias = true)
```
## Running a Simulation

As many parameters are already defined in the model, we only need to prepare time-series data for daily weather and irrigation, which are included in the package for convenience.

```@example simple
using CSV
using DataFrames
using Dates
using TimeZones

loaddata(f) = CSV.File(joinpath(dirname(pathof(SimpleCrop)), "../test/data", f)) |> DataFrame
; # hide
```

```@example simple
config = @config (
    :Clock => :step => 1u"d",
    :Calendar => :init => ZonedDateTime(1987, 1, 1, tz"UTC"),
    :Weather => :weather_data => loaddata("weather.csv"),
    :SoilWater => :irrigation_data => loaddata("irrigation.csv"),
)
; # hide
```
Let's run a simulation with the model using configuration we just created. Stop condition for simulation is defined in a flag variable named `endsim` which coincides with plant maturity or the end of reproductive stage.

```@example simple
r = simulate(SimpleCrop.Model; config, stop = :endsim)
; # hide
```
## Visualizing the Results 
The output of simulation is now contained in a data frame from which we generate multiple plots. The number of leaf (`N`) went from `initial_leaf_number` (= 2) to `maximum_leaf_number` (= 12) as indicated in the default set of parameters.

```@example simple
visualize(r, :DATE, :N; ylim = (0, 15), kind = :line)
```

Thermal degree days (`INT`) started accumulating from mid-August with the onset of reproductive stage until late-October when it reaches the maturity indicated by `duration_of_reproductive_stage` (= 300 K d).

```@example simple
visualize(r, :DATE, :INT; kind = :line)
```

Assimilated carbon (`W`) was partitioned into multiple parts of the plant as shown in the plot of dry biomass.

```@example simple
visualize(r, :DATE, [:W, :Wc, :Wr, :Wf];
    names = ["Total", "Canopy", "Root", "Fruit"], kind = :line)
```

Leaf area index (`LAI`) reached its peak at the end of vegetative stage then began declining throughout reproductive stage.

```@example simple
visualize(r, :DATE, :LAI; kind = :line)
```

For soil water balance, here is a plot showing water runoff (`ROF`), infiltration (`INF`), and vertical drainage (`DRN`).

```@example simple
visualize(r, :DATE, [:ROF, :INF, :DRN]; kind = :line)
```

Soil water status has influence on potential evapotranspiration (`ETp`), actual soil evaporation (`ESa`), and actual plant transpiration (`ESp`).

```@example simple
visualize(r, :DATE, [:ETp, :ESa, :EPa]; kind = :line)
```

The resulting soil water content (`SWC`) is shown here.

```@example simple
visualize(r, :DATE, :SWC; ylim = (0, 400), kind = :line)
```

Which, in turn, determines soil water stress factor (`SWFAC`) in this model.

```@example simple
visualize(r, :DATE, [:SWFAC, :SWFAC1, :SWFAC2]; ylim = (0, 1), kind = :line)
```


