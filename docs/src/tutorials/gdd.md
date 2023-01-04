```@setup Cropbox
using Cropbox
using CSV
using DataFrames
using Dates
using TimeZones

weather = DataFrame(
    "year" => Int.(2002*ones(139)),
    "doy" => [135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273],
    "rad (W/m^2)" => [295.8, 297.9, 224.2, 95.8, 314.9, 284.6, 275.0, 320.0, 318.5, 295.7, 226.1, 183.2, 203.4, 205.6, 209.8, 255.4, 274.0, 299.5, 294.5, 303.9, 268.1, 212.9, 192.4, 206.1, 242.1, 291.3, 282.2, 259.6, 236.1, 54.0, 50.0, 245.2, 237.5, 290.9, 257.1, 219.8, 248.3, 312.8, 297.8, 286.9, 282.4, 263.0, 222.4, 223.6, 183.7, 258.6, 261.1, 243.2, 257.3, 276.8, 275.9, 302.5, 299.9, 191.3, 240.2, 251.0, 146.8, 291.9, 311.6, 139.9, 86.3, 279.1, 294.8, 291.2, 172.0, 217.3, 225.9, 164.7, 232.5, 267.3, 124.2, 146.6, 77.5, 118.6, 243.5, 257.6, 256.6, 283.4, 284.3, 264.3, 187.6, 254.8, 210.9, 295.0, 256.9, 272.7, 275.0, 276.1, 259.7, 244.9, 248.2, 257.6, 226.2, 164.3, 195.4, 227.5, 241.6, 217.5, 209.3, 217.4, 168.0, 128.6, 229.4, 92.5, 129.3, 19.9, 65.7, 112.1, 126.7, 44.1, 146.1, 223.1, 226.6, 248.8, 244.8, 245.3, 204.7, 246.9, 232.0, 238.9, 240.7, 233.6, 106.7, 64.1, 147.8, 203.2, 192.0, 147.7, 157.4, 181.6, 161.8, 174.0, 215.9, 134.0, 32.0, 54.0, 205.7, 194.9, 143.1],
    "Tavg (°C)" => [14.9, 18.0, 21.3, 12.5, 9.6, 10.1, 8.8, 11.6, 14.7, 20.1, 20.3, 20.2, 21.6, 21.4, 21.8, 21.7, 25.8, 25.9, 23.1, 20.2, 22.8, 25.8, 23.5, 18.4, 17.5, 20.9, 24.9, 26.9, 25.9, 20.7, 18.4, 19.9, 19.8, 20.4, 20.7, 20.8, 21.7, 21.7, 22.4, 23.8, 26.1, 27.8, 27.8, 26.8, 23.5, 24.1, 24.0, 25.8, 27.9, 29.2, 29.9, 28.2, 23.1, 20.8, 23.5, 28.1, 24.9, 20.9, 20.5, 22.0, 20.8, 24.2, 26.7, 25.8, 27.1, 27.0, 26.0, 25.5, 27.7, 28.4, 23.4, 22.9, 20.0, 23.5, 28.1, 29.0, 27.9, 28.0, 27.9, 28.8, 25.9, 27.1, 27.1, 23.6, 20.0, 20.3, 21.4, 22.5, 25.0, 26.8, 27.9, 28.6, 28.7, 28.0, 28.2, 29.3, 28.2, 27.5, 25.4, 26.7, 27.1, 26.0, 25.4, 22.2, 23.9, 19.2, 17.7, 18.4, 19.9, 17.5, 19.3, 22.4, 24.9, 22.2, 20.3, 19.6, 19.8, 21.0, 23.8, 22.5, 17.5, 18.4, 21.3, 23.2, 23.4, 20.9, 20.5, 21.2, 22.8, 24.2, 23.7, 19.3, 16.3, 17.8, 17.5, 21.1, 20.2, 16.4, 17.9],
    "Tmax (°C)" => [22.1, 27.7, 27.3, 17.7, 15.6, 15.6, 14.5, 20.1, 24.0, 29.5, 24.6, 27.8, 27.7, 28.0, 27.7, 29.0, 32.3, 31.9, 29.1, 26.1, 28.7, 32.8, 32.4, 22.4, 24.3, 30.1, 32.7, 34.3, 32.8, 26.0, 20.6, 25.4, 26.8, 27.4, 28.8, 27.0, 28.4, 29.3, 30.0, 31.7, 34.2, 35.3, 34.9, 33.4, 29.0, 30.9, 31.5, 33.2, 35.3, 36.0, 36.4, 32.0, 29.6, 27.5, 32.7, 35.0, 29.0, 26.1, 29.7, 27.8, 24.4, 31.5, 32.7, 34.0, 32.7, 32.1, 32.2, 31.3, 34.6, 35.1, 28.6, 27.0, 21.6, 28.9, 35.0, 35.0, 33.1, 34.2, 35.6, 37.3, 35.9, 34.6, 35.0, 27.1, 26.3, 28.2, 29.6, 31.9, 34.5, 35.7, 36.9, 36.2, 34.8, 33.0, 33.8, 35.2, 34.7, 32.8, 31.1, 34.0, 31.4, 30.9, 31.1, 28.3, 29.7, 22.5, 21.1, 21.7, 25.2, 19.0, 24.0, 30.7, 31.7, 28.2, 26.8, 28.0, 29.6, 32.4, 32.8, 26.2, 25.4, 28.2, 27.3, 25.3, 29.8, 28.4, 28.4, 27.4, 29.2, 30.4, 29.7, 24.1, 25.5, 24.3, 19.3, 28.2, 25.4, 24.3, 24.0],
    "Tmin (°C)" => [8.6, 4.9, 14.3, 8.0, 4.0, 4.3, 2.6, 1.4, 3.0, 7.1, 16.1, 15.5, 17.2, 15.9, 15.3, 13.8, 17.9, 17.9, 15.4, 11.4, 16.8, 19.0, 17.8, 12.6, 11.3, 11.2, 16.1, 18.8, 18.4, 17.7, 16.7, 14.5, 12.0, 12.1, 12.5, 15.4, 15.2, 14.1, 13.9, 14.7, 17.9, 19.6, 22.3, 22.0, 19.9, 17.6, 15.9, 18.0, 19.7, 22.4, 22.3, 22.1, 15.3, 13.2, 13.3, 19.8, 21.4, 13.5, 10.4, 15.6, 18.1, 16.6, 19.7, 16.8, 21.1, 21.8, 21.1, 19.9, 19.3, 22.2, 20.2, 20.8, 16.9, 19.9, 21.9, 22.1, 21.9, 22.2, 19.8, 19.9, 21.1, 19.5, 21.1, 17.4, 13.1, 12.2, 12.9, 12.6, 15.6, 17.9, 19.7, 22.2, 21.9, 24.0, 22.4, 23.4, 21.5, 22.3, 18.7, 18.9, 23.3, 22.4, 20.4, 17.4, 17.4, 15.6, 15.3, 14.6, 15.2, 15.6, 14.6, 14.0, 18.2, 16.6, 15.0, 12.2, 13.3, 11.4, 15.3, 16.6, 9.0, 8.4, 14.3, 21.9, 18.2, 15.2, 14.1, 15.8, 16.5, 17.1, 18.6, 10.1, 7.8, 10.5, 15.7, 15.2, 13.2, 10.4, 12.2],
    "rainfall (mm)" => [0, 0, 3, 11, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 1, 6, 0, 0, 0, 0, 0, 0, 9, 3, 4, 0, 0, 7, 7, 0, 0, 0, 0, 0, 0, 0, 6, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 28, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 12, 1, 0, 0, 0, 0, 0, 0, 10, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 42, 3, 0, 1, 35, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 5, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 26, 6, 0, 0, 0],
    "date (:Date)" => Date("2002-05-15"):Day(1):Date("2002-09-30"),
    "GDD (K)" => [6.9, 10.0, 13.3, 4.5, 1.6, 2.1, 0.8, 3.6, 6.7, 12.1, 12.3, 12.2, 13.6, 13.4, 13.8, 13.7, 17.8, 17.9, 15.1, 12.2, 14.8, 17.8, 15.5, 10.4, 9.5, 12.9, 16.9, 18.9, 17.9, 12.7, 10.4, 11.9, 11.8, 12.4, 12.7, 12.8, 13.7, 13.7, 14.4, 15.8, 18.1, 19.8, 19.8, 18.8, 15.5, 16.1, 16.0, 17.8, 19.9, 21.2, 21.9, 20.2, 15.1, 12.8, 15.5, 20.1, 16.9, 12.9, 12.5, 14.0, 12.8, 16.2, 18.7, 17.8, 19.1, 19.0, 18.0, 17.5, 19.7, 20.4, 15.4, 14.9, 12.0, 15.5, 20.1, 21.0, 19.9, 20.0, 19.9, 20.8, 17.9, 19.1, 19.1, 15.6, 12.0, 12.3, 13.4, 14.5, 17.0, 18.8, 19.9, 20.6, 20.7, 20.0, 20.2, 21.3, 20.2, 19.5, 17.4, 18.7, 19.1, 18.0, 17.4, 14.2, 15.9, 11.2, 9.7, 10.4, 11.9, 9.5, 11.3, 14.4, 16.9, 14.2, 12.3, 11.6, 11.8, 13.0, 15.8, 14.5, 9.5, 10.4, 13.3, 15.2, 15.4, 12.9, 12.5, 13.2, 14.8, 16.2, 15.7, 11.3, 8.3, 9.8, 9.5, 13.1, 12.2, 8.4, 9.9],
    "cGDD (K)" => [6.9, 10.0, 13.3, 4.5, 1.6, 2.1, 0.8, 3.6, 6.7, 12.1, 12.3, 12.2, 13.6, 13.4, 13.8, 13.7, 17.8, 17.9, 15.1, 12.2, 14.8, 17.8, 15.5, 10.4, 9.5, 12.9, 16.9, 18.9, 17.9, 12.7, 10.4, 11.9, 11.8, 12.4, 12.7, 12.8, 13.7, 13.7, 14.4, 15.8, 18.1, 19.8, 19.8, 18.8, 15.5, 16.1, 16.0, 17.8, 19.9, 21.2, 21.9, 20.2, 15.1, 12.8, 15.5, 20.1, 16.9, 12.9, 12.5, 14.0, 12.8, 16.2, 18.7, 17.8, 19.1, 19.0, 18.0, 17.5, 19.7, 20.4, 15.4, 14.9, 12.0, 15.5, 20.1, 21.0, 19.9, 20.0, 19.9, 20.8, 17.9, 19.1, 19.1, 15.6, 12.0, 12.3, 13.4, 14.5, 17.0, 18.8, 19.9, 20.6, 20.7, 20.0, 20.2, 21.3, 20.2, 19.5, 17.4, 18.7, 19.1, 18.0, 17.4, 14.2, 15.9, 11.2, 9.7, 10.4, 11.9, 9.5, 11.3, 14.4, 16.9, 14.2, 12.3, 11.6, 11.8, 13.0, 15.8, 14.5, 9.5, 10.4, 13.3, 15.2, 15.4, 12.9, 12.5, 13.2, 14.8, 16.2, 15.7, 11.3, 8.3, 9.8, 9.5, 13.1, 12.2, 8.4, 9.9]
)
```

# [Growing Degree-Day](@id GDD)

You might have heard the terms like growing degree days (GDD), thermal units, heat units, heat sums, temperature sums, and thermal-time that are used to relate the rate of plant or insect development to temperature. They are all synonymous. The concept of thermal-time or thermal-units derives from the long-standing observation and assumption that timing of development is primarily driven by temperature in plants and the relationship is largely linear. The linear relationship is generally held true over normal growing temperatures that are bracketed by the base temperature (*Tb*) and optimal temperature (*Topt*). Many existing crop models and tree growth models use thermal-unit approaches (e.g., GDD) for modeling phenology with some modifications to account for other factors like photoperiod, vernalization, dormancy, and stress. The growing degree days (GDD) is defined as the difference between the average daily air temperature (*T*) and the base temperature below which the developmental process stops. The bigger the difference in a day, the faster the development takes place up to a certain optimal temperature (*Topt*). The Cumulative GDD (cGDD) since the growth initiation (e.g., sowing, imbibition for germination) is then calculated by:

```math
\begin{align}
\mathrm{GDD}(T) &= \max \{ 0, \min \{ T, T_{opt} \} - T_b \} \\
\mathrm{cGDD} &= \sum_i^n \mathrm{GDD}(T_i) \\
\end{align}
```

In this tutorial, we will create a model that simulates GDD and cGDD.

Let us start by making a system called `GrowingDegreeDay`.
```
@system GrowingDegreeDay
```

From the equation, let's identify the variables we need to declare in our system. In the equation for GDD, we have two parameters *Topt* and *Tb*. Since they are fixed values, we will declare them as `preserve` variables, which are variables that remain constant throughout a simulation.

```
@system GrowingDegreeDay begin
    Tb ~ preserve
    To ~ preserve
end
```

 `Tb` and `To` are parameters that we may want to change depending on the simulation. To make this possible, we will assign them the `parameter` tag, which allows the tagged variables to be altered through a configuration for each simulation. Note that we will not assign values at declaration because we will configure them when we run the simulation.

  ```
@system GrowingDegreeDay begin
    Tb ~ preserve(parameter)
    To ~ preserve(parameter)
end
```
 
 Lastly, we will tag the variables with units. Tagging units is the recommended practice for many reasons, one of which is to catch mismatching units during calculations.
 
 ```
@system GrowingDegreeDay begin
    Tb ~ preserve(parameter, u"°C")
    To ~ preserve(parameter, u"°C")
end
```

In the GDD equation, *T* represents the average daily temperature value necessary to calculate the GDD. Likewise, the variable in our system will represent a series of daily average temperatures. The series of temperature values will be driven from an external data source, for which we will create a separate system later on for data extraction. For the `GrowingDegreeDay` system, we will declare `T` as a `hold` variable, which represents a placeholder that will be replaced by a `T` from another system. 

```
@system GrowingDegreeDay begin
    T ~ hold
    Tb ~ preserve(parameter, u"°C")
    To ~ preserve(parameter, u"°C")
end
```

We declared all the necessary variables required to calculate GDD. Now it is time to declare GDD as a variable in the system. Because GDD is a variable that we want to evaluate and store in each update, we will declare it as a `track` variable with `T`, `Tb`, and `To` as its depending variables.

```
@system GrowingDegreeDay begin
    T ~ hold
    Tb ~ preserve(parameter, u"°C")
    To ~ preserve(parameter, u"°C")

    GDD(T, Tb, To) => begin
        min(T, To) - Tb
    end ~ track(min = 0, u"K")
end
```

*Note that we have tagged the unit for* `GDD` *as* `u"K"`. *This is to avoid incompatibilities that* `u"°C"` *has with certain operations.*

Now that `GDD` is declared in the system, we will declare cGDD as an `accumulate` variable with `GDD` as its depending variable. Recall that `accumulate` variables perform the Euler method of integration.

```
@system GrowingDegreeDay begin
    T ~ hold
    Tb ~ preserve(parameter, u"°C")
    To ~ preserve(parameter, u"°C")

    GDD(T, Tb, To) => begin
        min(T, To) - Tb
    end ~ track(min = 0, u"K")

    cGDD(GDD) ~ accumulate(u"K*d")
end
```

We have declared all the necessary variables for `GrowingDegreeDay`. 

Now let's address the issue of the missing temperature values. We will make a new system that will provide the missing temperature data we need for simulating `GrowingDegreeDay`. We will call this system `Temperature`. The purpose of `Temperature` will be to obtain a time series of daily average temperature values from an external data source.

```
@system Temperature
```

For this tutorial, we will be using the following DataFrame, containing weather data from Beltsville, Maryland in 2002.

```@example Cropbox
first(weather, 3)
```
\

Notice that the column names have units in parentheses. The `unitfy()` function in Cropbox automatically assigns units to values based on names of the columns (if the unit is specified).

```@example Cropbox
weather = unitfy(weather)
first(weather, 3)
```
\

In the `Temperature` system, there is one variable that we will declare before declaring any other variable. We will name this variable `calendar`.

```
@system Temperature begin
    calendar(context) ~ ::Calendar
end
```

The purpose of `calendar` is to have access to variables inside the `Calendar` system such as `init`, `last`, and `date`, which represent initial, last, and current date, respectively.

!!! note "Note"
    `calendar` is a variable reference to the [`Calendar`](@ref Calendar) system (one of the built-in systems of Cropbox), which has a number of time-related variables in date format. Declaring `calendar` as a variable of type `Calendar` allows us to use the variables inside the `Calendar` system as variables for our current system. Recall that `context` is a reference to the `Context` system and is included in every Cropbox system by default. Inside the `Context` system there is the `config` variable which references a `Config` object. By having `context` as a depending variable for `calendar`, we can change the values of the variables in `calendar` with a configuration. 

The next variable we will add is a variable storing the weather data as a DataFrame. This variable will be a `provide` variable named `data`.

```
@system Temperature begin
    calendar(context) ~ ::Calendar
    data ~ provide(parameter, index=:date, init=calendar.date)
end
```

 Note that we have tagged the variable with a `parameter` tag so that we can assign a DataFrame during the configuration. We will set the index of the extracted DataFrame as the "date" column of the data source. The `init` tag is used to specify the starting row of the data that we want to store. `calendar.date` refers to the `date` variable in the `Calendar` system, and is a `track` variable that keeps track of the dates of simulation. The initial value of `date` is dependent on `calendar.init` which we will assign during configuration. By setting `init` to `calendar.date`, we are making sure that the `provide` variable extracts data from the correct starting row corresponding to the desired initial date of simulation.

Now we can finally declare the temperature variable using one of the columns of the DataFrame represented by `data`. Because this variable is *driven* from a source, we will be declaring a `drive` variable named `T`. The `from` tag specifies the DataFrame source and the `by` tag specifies which column to take the values from.

```@example Cropbox
@system Temperature begin
    calendar(context) ~ ::Calendar
    data ~ provide(parameter, index=:date, init=calendar.date)
    T ~ drive(from=data, by=:Tavg, u"°C")
end
```
\

We finally have all the components to define our model. Because `GrowingDegreeDay` requires values for `T` from `Temperature`, let's redeclare `GrowingDegreeDay` with `Temperature` as a mixin. Because we want to run a simulation of `GrowingDegreeDay`, we also want to include `Controller` as a mixin. Recall that `Controller` must be included as a mixin for any system that you want to simulate.

```@example Cropbox
@system GrowingDegreeDay(Temperature, Controller) begin
    T ~ hold
    Tb ~ preserve(parameter, u"°C")
    To ~ preserve(parameter, u"°C")

    GDD(T, Tb, To) => begin
        min(T, To) - Tb
    end ~ track(min = 0, u"K")

    cGDD(GDD) ~ accumulate(u"K*d")
end
```
\

**Configuration**

The next step is to create a configuration object to assign the values of parameters. Recall that `data`, `T`, `Tb`, and `To` are empty variables at the moment.

As covered in the [Configuration](@ref Configuration1) section, we can make a single `Config` object with all the configurations we need for our systems.

Given the nature of GDD, this model is a daily model. To run a daily simulation, we need to configure the `step` variable in the `Clock` system from `1u"hr"` to `1u"d"`. This will change the time interval of the simulation from hourly (default) to daily.

```
c = @config :Clock => :step => 1u"d"
```

Next we will add the configurations for `GrowingDegreeDay`. The only parameters we have to configure are `Tb` and `To`.

```
c = @config (
    :Clock => (
        :step => 1u"d"
    ),
    :GrowingDegreeDay => (
        :Tb => 8.0u"°C",
        :To => 32.0u"°C"
    )
)
```

Next we will pair the aforementioned DataFrame `weather` to `data` in `Temperature`

```
c = @config(
    :Clock => (
        :step => 1u"d"
    ),
    :GrowingDegreeDay => (
        :Tb => 8.0u"°C",
        :To => 32.0u"°C"
    ),
    :Temperature => (
        :data => weather
    )
)
```

Lastly, we will configure the `init` and `last` parameters of the `Calendar` system, which will define the time range of our simulation.

```@example Cropbox
c = @config(
    :Clock => (
        :step => 1u"d"
    ),
    :GrowingDegreeDay  => (
        :Tb => 8.0u"°C",
        :To => 32.0u"°C"
    ),
    :Temperature => (
        :data => weather
    ),
    :Calendar => (
        :init => ZonedDateTime(2002, 5, 15, tz"America/New_York"),
        :last => ZonedDateTime(2002, 9, 30, tz"America/New_York")
    )
)
```

**Simulation**

Now that we have fully defined `GrowingDegreeDay` and created a configuration for it, we can finally simulate the model.

```@example Cropbox
s = simulate(GrowingDegreeDay;
    config = c,
    stop = "calendar.stop",
    index = "calendar.date",
    target = [:GDD, :cGDD]
)

first(s, 10)
```
\

**Visualization**

To end the tutorial, let's visualize the simulation using the `plot()` and `visualize()` functions.

We can input the DataFrame from our simulation in the `plot()` function to create a plot.

Here is a plot of `GDD` over time.

```@example Cropbox
plot(s, "calendar.date", :GDD; kind=:line)
```

We can also simultaneously run a new simulation and plot its result using the `visualize()` function.

Here is a plot of `cGDD` over time.

```@example Cropbox
visualize(GrowingDegreeDay, "calendar.date", :cGDD; config=c, stop="calendar.stop", kind=:line)
```