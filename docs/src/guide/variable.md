# Variables

In Cropbox, a variable is defined as a unit element of modeling that denotes a value determined by a specific operation relying on other variables. Each variable represents a field within the system struct defined by the `@system` macro.

## Variable Declaration

Variables are declared when a system is declared with the `@system` macro. `@system` macro accepts lines of variable declaration specified by its own syntax. They are loosely based on Julia syntax sharing common expressions and operators, but have distinct semantics as explained below.

`name[(args..; kwargs..)][: alias] [=> body] ~ [state][::type][(tags..)]`

- `name`: variable name (usually short abbreviation)
- `args`: automatically bound depending variables
- `kwargs`: custom bound depending variables (only for *call* now)
- `alias`: alternative name (long description)
- `body`: code snippet (state/type specific, `begin .. end` block for multiple lines)
- `state`: verb indicating kind of state (empty if not `State`-based)
- `type`: internal type (*i.e.* `Float64` by default for most `State` variable)
- `tags`: variable specific options (*i.e.* unit, min/max, etc.)

```@setup Cropbox
using Cropbox
using DataFrames
```

## State

Within Cropbox, a variable inside a system can be one of many different abstract types based on the variable's purpose. Depending on its type, each variable has its own behavior when a system is instantiated. In Cropbox, we refer to these as the *state* of the variables, originating from the term *state variables* often used in mathematical modeling.

!!! note "Note"
    Specifying a *state* is not mandatory when declaring a variable. Cropbox also allows plain variables, which are commonly used for creating variable references to other systems.

Currently, there are 19 different variable states implemented in Cropbox.

*Instant derivation*
 - `preserve`: keeps an initially assigned value with no further updates; constants, parameters
 - `track` : evaluates expression and assigns a new value for each time step
 - `flag` : checks a conditional logic; similar to track with boolean type, but composition is allowed
 - `remember` : keeps tracking the variable until a certain condition is met; like track switching to preserve

*Cumulative update*
 - `accumulate`: emulates integration of a rate variable over time; essentially Euler method
 - `capture` : calculates the difference of accumulate between time steps
 - `integrate` : calculates an integral over a non-time variable using Gaussian method
 - `advance` : updates an internal time-keeping variable

*Data source*
 - `provide` : provides a table-like multi-column time-series data; i.e. weather data
 - `drive` : fetches the current value from a time-series; often used with provide; i.e. air temperature
 - `tabulate` : makes a two dimensional table with named keys; i.e. partitioning table
 - `interpolate` : makes a curve function interpolated with discrete values; i.e. soil characteristic curve

 *Equation solving*
 - `solve` : solves a polynomial equation symbolically; *i.e.* quadratic equation for coupling photosynthesis
 - `bisect` : solves a nonlinear equation using bisection method; *i.e.* energy balance equation

 *Dynamic structure*
 - `produce` : attaches a new instance of dynamically generated system; *i.e.* root structure growth

 *Language extension*
 - `hold`: marks a placeholder for the variable shared between mixins
 - `wrap` : allows passing a reference to the state variable object, not a dereferenced value
 - `call` : defines a partial function accepting user-defined arguments, while bound to other variables
 - `bring` : duplicates variables declaration from another system into the current system

### *Instant derivation*

#### [`preserve`](@id preserve)

`preserve` variables are fixed values with no further modification after instantiation of a system. Consequently, they are often used as the `state` for `parameter` variables, which allow any initial value to be set via a configuration object supplied at the start of a simulation. Non-parameter constants are also used for fixed variables that do not need to be computed at each time step.

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve
end

simulate(S; stop=3u"hr")
```
Supported tags: [`unit`](@ref unit), [`optional`](@ref optional), [`parameter`](@ref parameter), [`override`](@ref override), [`extern`](@ref extern), [`ref`](@ref ref), [`min`](@ref min), [`max`](@ref max), [`round`](@ref round)

#### [`track`](@id track)

`track` variables are evaluated and assigned a new value at every time step. In a conventional model, these are the variables that would be computed in every update loop. At every time step, the formula in the variable code is evaluated and saved for use. This assignment of value occurs only *once* per time step, as intended by the Cropbox framework. No manual assignment of computation at an arbitrary time is allowed. This is to ensure that that there are no logical errors resulting from premature or incorrectly ordered variable assignments. For example, a cyclical reference between two `track` variables is caught by Cropbox as an error. In many procedural programming languages, such logical errors are still valid and go unnoticed even after model completion.

**Example**

In this example, we can see that the variable `b` keeps track of the most recent iteration of the variable `a`.

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ accumulate
    b(a) => a ~ track
end

simulate(S; stop=3u"hr")
```
Supported tags: [`unit`](@ref unit), [`override`](@ref override), [`extern`](@ref extern), [`ref`](@ref ref), [`skip`](@ref skip), [`init`](@ref init), [`min`](@ref min), [`max`](@ref max), [`round`](@ref round), [`when`](@ref when)

#### [`flag`](@id flag)

`flag` variables are expressed in a conditional statement or logical operator for which a boolean value is evaluated at every time step. They function like a `track` variable but with a boolean value.

**Example**

In this example, the `FLAG` variable evaluates `a > b` and saves the resulting boolean value at each time step.

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ accumulate
    b => 2 ~ preserve

    FLAG(a, b) => (a > b) ~ flag
end

simulate(S; stop=3u"hr")
```
Supported tags: [`parameter`](@ref parameter), [`override`](@ref override), [`extern`](@ref extern), [`once`](@ref once), [`when`](@ref when)


#### [`remember`](@id remember)

`remember` variables are values that are evaluated until a specified condition is met. They are like track variables that turn into preserve variables.

**Example**
```@example Cropbox
@system S(Controller) begin
    t(context.clock.tick) ~ track
    w(t) => t >= 2 ~ flag
    i => -1 ~ preserve
    r(t) ~ remember(init=i, when=w)
end

simulate(S; stop=3u"hr")
```
Supported tags: [`unit`](@ref unit), [`init`](@ref init), [`when`](@ref when)


### *Cumulative update*

#### [`accumulate`](@id accumulate)

`accumulate` variables emulate the integration of a rate variable over time. It uses the Euler's method of integration. By default, an `accumulate` variable accumulates every hour, unless a time unit is specified.

**Example**

In this example, both `a` and ``b` are `accumulate` variables that increase by 1. Because `b` has a time unit of `u"d"` specified, it accumulates at 1/24 the rate of `a`.

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ accumulate
    b => 1 ~ accumulate(u"d")
end

simulate(S; stop=3u"hr")
```
Supported tags: [`unit`](@ref unit), [`init`](@ref init), [`time`](@ref time), [`timeunit`](@ref timeunit), [`reset`](@ref reset), [`min`](@ref min), [`max`](@ref max), [`when`](@ref when)


### *Data source*

#### [`provide`](@id provide)

`provide` variables provide a DataFrame with a given index (`index`) starting from an initial value (`init`).

**Example**
```@example Cropbox
@system S(Controller) begin
    D => DataFrame(index=(0:3)u"hr", value=0:10:30) ~ provide
end

instance(S)
```
Supported tags: [`index`](@ref index), [`init`](@ref init), [`step`](@ref step), [`autounit`](@ref autounit), [`parameter`](@ref parameter)


#### [`drive`](@id drive)

`drive` variables fetch the current value from a time-series. It is often used in conjunction with `provide`.

**Example**
```@example Cropbox
@system S(Controller) begin
    a => [2, 4, 6] ~ drive
end

instance(S)
```
Supported tags: [`tick`](@ref tick), [`unit`](@ref unit), [`from`](@ref from), [`by`](@ref by), [`parameter`](@ref parameter), [`override`](@ref override)


#### [`tabulate`](@id tabulate)

`tabulate` variables make a two dimensional table with named keys.

**Example**
```@example Cropbox
@system S(Controller) begin
    T => [
      # a b
        0 4 ; # A
        1 5 ; # B
        2 6 ; # C 
        3 7 ; # D
    ] ~ tabulate(rows=(:A, :B, :C, :D), columns=(:a, :b))
end
```
Supported tags: [`unit`](@ref unit), [`rows`](@ref rows), [`columns`](@ref columns), [`parameter`](@ref parameter)


#### [`interpolate`](@id interpolate)

`interpolate` variables make a curve function for a provided set of discrete values.

**Example**
```@example Cropbox
@system S(Controller) begin
    m => ([1 => 10, 2 => 20, 3 => 30]) ~ interpolate
    n(m) ~ interpolate(reverse)
    a(m) => m(2.5) ~ track
    b(n) => n(25) ~ track
end

simulate(S; stop=3u"hr")
```
Supported tags: [`unit`](@ref unit), [`knotunit`](@ref knotunit), [`reverse`](@ref reverse), [`parameter`](@ref parameter)


### *Equation solving*

#### [`solve`](@id solve)

`solve` variables solve a polynomial equation symbolically.

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve(parameter)
    b => 2 ~ preserve(parameter)
    c => 4 ~ preserve(parameter)
    x(a, b, c) => begin
        a*x^2 + b*x + c
    end ~ solve
end

instance(S)
```
Supported tags: [`unit`](@ref unit), [`lower`](@ref lower), [`upper`](@ref upper), [`pick`](@ref pick)


#### [`bisect`](@id bisect)

`bisect` variables solve a nonlinear equation using the bisection method.

**Example**
```@example Cropbox
@system S(Controller) begin
    x(x) => x - 1 ~ bisect(lower=0, upper=2)
end

instance(S)
```
Supported tags: [`unit`](@ref unit), [`evalunit`](@ref evalunit), [`lower`](@ref lower), [`upper`](@ref upper), [`maxiter`](@ref maxiter), [`tol`](@ref tol), [`min`](@ref min), [`max`](@ref max)


### *Dynamic structure*

#### [`produce`](@id produce)

`produce` variables attach a new instance of a dynamically generated system.

**Example**

In this example, we produce a system `S` which we can reference with a new variable in another system.

```@example Cropbox
@system S begin
    a => produce(S) ~ produce
end

@system SController(Controller) begin
    s(context) ~ ::S
end
```
Supported tags: [`single`](@ref single), [`when`](@ref when)


### *Language extension*

#### `hold`

`hold` variables are placeholders for variables that are supplied by another system as a mixin.

**Example**

In `S2`, using `a` as a `hold` variable allows us to declare `b` which depends on `a` for evaluation. Using `S1` as a mixin for `S2` actually allows us to instantiate `S2` because `S1` contains an `advance` variable `a`.

```@example Cropbox
@system S1 begin
    a ~ advance
end

@system S2(S1, Controller) begin
    a ~ hold
    b(a) => a ~ track
end

simulate(S2; stop=3u"hr")
```
Supported tags: None


#### `wrap`

`wrap` allows passing a reference to the state variable object, not a dereferenced value

**Example**
```@example Cropbox
```
Supported tags: None


#### [`call`](@id call)

`call` defines a partial function accepting user-defined arguments

**Example**
```@example Cropbox
```
Supported tags: [`unit`](@ref unit)


#### [`bring`](@id bring)

`bring` duplicates variable declaration from another system into the current system

**Example**
```@example Cropbox
```
Supported tags: [`parameters`](@ref parameters), [`override`](@ref override)


## Tag

Apart from a few, most variable states have tags that can be specified in the form of `(tag)` to add additional features. The available tags vary between variable states. Some tags are shared by multiple variable states while some tags are exclusive to certain variable states.

### [`autounit`](@id autounit)

`autounit` tag allows provide variables to automatically assign units to variables depending on column headers of the DataFrame.

Used by: [`provide`](@ref provide)

### [`by`](@id by)

`by` tag is used to specify which column and series from which the `drive` variable should be driven.

Used by: [`drive`](@ref drive)

### [`columns`](@id columns)

`columns`

Used by: [`tabulate`](@ref tabulate)

### [`evalunit`](@id evalunit)

`evalunit`

Used by: [`bisect`](@ref bisect)

### [`extern`](@id extern)

`extern`

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`flag`](@ref flag)

### [`from`](@id from)

`from` tag is used to specify the DataFrame that the `drive` variable will be driven from.

Used by: [`drive`](@ref drive)

### [`index`](@id index)

`index`, combined with `init`, is used by `provide` variables to specify the index and initial value of the DataFrame from which the data will be provided.

Used by: [`provide`](@ref provide)

### [`init`](@id init)

`init` assigns the first value to be used for the variable at the time of instantiation.

`init`

Used by: [`track`](@ref track), [`remember`](@ref remember), [`accumulate`](@ref accumulate), [`provide`](@ref provide)

### [`knotunit`](@id knotunit)

`knotunit`

Used by: [`interpolate`](@ref interpolate)

### [`lower`](@id lower)

`lower` tag is used to specify the lower bound of the solution for `solve` and `bisect` variables.

Used by: [`solve`](@ref solve), [`bisect`](@ref bisect)

### [`max`](@id max)

`max` Determines the minimum possible value of variable evaluation.

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`accumulate`](@ref accumulate), [`bisect`](@ref bisect)

### [`maxiter`](@id maxiter)

`maxiter` tag defines the maximum number of iterations for the

Used by: [`bisect`](@ref bisect)

### [`min`](@id min)

`min` Determines the minimum possible value of variable evaluation.

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`accumulate`](@ref accumulate), [`bisect`](@ref bisect)


### [`optional`](@id optional)

Used by: [`preserve`](@ref preserve)

### [`override`](@id override)

`override`

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`flag`](@ref flag), [`drive`](@ref drive), [bring](@ref bring)

### [`parameter`](@id parameter)

Variables with the `parameter` tag can be altered with a [configuration](@ref Configuration) at the time of system instantiation.

Used by: [`preserve`](@ref preserve), [`flag`](@ref flag), [`provide`](@ref provide), [`drive`](@ref drive), [`tabulate`](@ref tabulate), [`interpolate`](@ref interpolate)

### [`parameters`](@id parameters)

`parameters`

Used by: [`bring`](@ref bring)

### [`pick`](@id pick)

`pick`

Used by: [`solve`](@ref solve)

### [`ref`](@id ref)

Used by: [`preserve`](@ref preserve), [`track`](@ref track)

### [`reset`](@id reset)

`reset`

Used by: [`accumulate`](@ref accumulate)

### [`reverse`](@id reverse)

`reverse`

Used by: [`interpolate`](@ref interpolate)

### [`round`](@id round)

Used by: [`preserve`](@ref preserve), [`track`](@ref track)

### [`rows`](@id rows)

`rows`

Used by: [`tabulate`](@ref tabulate)

### [`single`](@id single)

`single`

Used by: [`produce`](@ref produce)

### [`step`](@id step)

`step`

Used by: [`provide`](@ref provide)

### [`tick`](@id tick)

`tick`

Used by: [`drive`](@ref drive)

### [`time`](@id time)

`time`

Used by: [`accumulate`](@ref accumulate)

### [`timeunit`](@id timeunit)

`timeunit`

Used by: [`accumulate`](@ref accumulate)

### [`tol`](@id tol)

`tol`

Used by: [`bisect`](@ref bisect)

### [`unit`](@id unit)

`unit` tag is used to specify the unit of the variable.

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`remember`](@ref remember), [`accumulate`](@ref accumulate), [`drive`](@ref drive), [`tabulate`](@ref tabulate), [`interpolate`](@ref interpolate), [`solve`](@ref solve), [`bisect`](@ref bisect), [`call`](@ref call)

### [`upper`](@id upper)

`upper` tag is used to specify the upper bound of solution

Used by: [`solve`](@ref solve), [`bisect`](@ref bisect)

### [`when`](@id when)

`when` tag is used to specify when a variable should be evaluated. It is supplied with a `flag` variable, and the specified variable is only evaluated when the `flag` variable is `true`.

**Example**
```@example Cropbox

```

Used by: [`track`](@ref track), [`flag`](@ref flag), [`remember`](@ref remember), [`accumulate`](@ref accumulate), [`produce`](@ref produce)