```@setup Cropbox
using Cropbox
using DataFrames
```

# [Variable](@id variable)

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

**Example**

Here is an example of a system declaration where all three variables are valid declarations:

```@example Cropbox
@system S begin
    a: variable_a ~ advance
    b(a) => a^2 ~ track
    c => true ~ ::Bool
end
```

## Variable States

Within Cropbox, a variable inside a system can be one of many different abstract types based on the variable's purpose. Depending on its type, each variable has its own behavior when a system is instantiated. In Cropbox, we refer to these as the *state* of the variables, originating from the term *state variables* often used in mathematical modeling.

!!! note "Note"
    Specifying a *state* is not mandatory when declaring a variable. Cropbox also allows plain variables, which are commonly used for creating variable references to other systems. 

Currently, there are 19 different variable states implemented in Cropbox.

*Instant derivation*
 - [`preserve`](@ref preserve): keeps an initially assigned value with no further updates; constants, parameters
 - [`track`](@ref track) : evaluates expression and assigns a new value for each time step
 - [`flag`](@ref flag) : checks a conditional logic; similar to track with boolean type, but composition is allowed
 - [`remember`](@ref remember) : keeps tracking the variable until a certain condition is met; like track switching to preserve

*Cumulative update*
 - [`accumulate`](@ref accumulate): emulates integration of a rate variable over time; essentially Euler method
 - [`capture`](@ref capture): calculates the difference between time steps
 - [`integrate`](@ref integrate): calculates an integral over a non-time variable using Gaussian method
 - [`advance`](@ref advance): updates an internal time-keeping variable

*Data source*
 - [`provide`](@ref provide): provides a table-like multi-column time-series data; i.e. weather data
 - [`drive`](@ref drive): fetches the current value from a time-series; often used with provide; i.e. air temperature
 - [`tabulate`](@ref tabulate): makes a two dimensional table with named keys; i.e. partitioning table
 - [`interpolate`](@ref interpolate): makes a curve function interpolated with discrete values; i.e. soil characteristic curve

 *Equation solving*
 - [`solve`](@ref solve): solves a polynomial equation symbolically; *i.e.* quadratic equation for coupling photosynthesis
 - [`bisect`](@ref bisect): solves a nonlinear equation using bisection method; *i.e.* energy balance equation

 *Dynamic structure*
 - [`produce`](@ref produce): attaches a new instance of dynamically generated system; *i.e.* root structure growth

 *Language extension*
 - [`hold`](@ref hold): marks a placeholder for the variable shared between mixins
 - [`wrap`](@ref wrap): allows passing a reference to the state variable object, not a dereferenced value
 - [`call`](@ref call): defines a partial function accepting user-defined arguments, while bound to other variables
 - [`bring`](@ref bring): duplicates variables declaration from another system into the current system

### *Instant derivation*

#### [`preserve`](@id preserve)

`preserve` variables are fixed values with no further modification after instantiation of a system. As a result, they are often used as the `state` for `parameter` variables, which allow any initial value to be set via a configuration object supplied at the start of a simulation. Non-parameter constants are also used for fixed variables that do not need to be computed at each time step.

Supported tags: [`unit`](@ref unit), [`optional`](@ref optional), [`parameter`](@ref parameter), [`override`](@ref override), [`extern`](@ref extern), [`ref`](@ref ref), [`min`](@ref min), [`max`](@ref max), [`round`](@ref round)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve
end

simulate(S; stop=2)
```
\

#### [`track`](@id track)

`track` variables are evaluated and assigned a new value at every time step. In a conventional model, these are the variables that would be computed in every update loop. At every time step, the formula in the variable code is evaluated and saved for use. This assignment of value occurs only *once* per time step, as intended by the Cropbox framework. No manual assignment of computation at an arbitrary time is allowed. This is to ensure that that there are no logical errors resulting from premature or incorrectly ordered variable assignments. For example, a cyclical reference between two `track` variables is caught by Cropbox as an error.

Supported tags: [`unit`](@ref unit), [`override`](@ref override), [`extern`](@ref extern), [`ref`](@ref ref), [`skip`](@ref skip), [`init`](@ref init), [`min`](@ref min), [`max`](@ref max), [`round`](@ref round), [`when`](@ref when)

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ advance
    b(a) => 2*a ~ track
end

simulate(S; stop=2)
```
\

#### [`flag`](@id flag)

`flag` variables are expressed in a conditional statement or logical operator for which a boolean value is evaluated at every time step. They function like a `track` variable but with a boolean value.

Supported tags: [`parameter`](@ref parameter), [`override`](@ref override), [`extern`](@ref extern), [`once`](@ref once), [`when`](@ref when)

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ advance
    b => 1 ~ preserve

    f(a, b) => (a > b) ~ flag
end

simulate(S; stop=2)
```
\

#### [`remember`](@id remember)

`remember` variables keep track of a variable until a specified condition is met. When the condition is met, it is saved as either its latest update or a specified value. They are like track variables that turn into preserve variables. The `when` tag is required to specify condition. Unless specified, the initial value for `remember` defaults to `0`.

Supported tags: [`unit`](@ref unit), [`init`](@ref init), [`when`](@ref when)

**Example**
```@example Cropbox
@system S(Controller) begin
    t(context.clock.tick) ~ track
    f(t) => t > 1 ~ flag
    r1(t) ~ remember(when=f)
    r2(t) => t^2 ~ remember(when=f)
end

simulate(S; stop=2)
```
\

### *Cumulative update*

#### [`accumulate`](@id accumulate)

`accumulate` variables emulate the integration of a rate variable over time. It uses the Euler's method of integration. By default, an `accumulate` variable accumulates every hour, unless a unit of time is specified.

Supported tags: [`unit`](@ref unit), [`init`](@ref init), [`time`](@ref time), [`timeunit`](@ref timeunit), [`reset`](@ref reset), [`min`](@ref min), [`max`](@ref max), [`when`](@ref when)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ accumulate
    b => 1 ~ accumulate(u"d")
end

simulate(S; stop=2)
```
\

#### [`capture`](@id capture)

`capture` variables calculate the difference of a variable between time steps. The `time` tag allows evaluations for varying rates of time.

Supported tags: [`unit`](@ref unit), [`time`](@ref time), [`timeunit`](@ref timeunit), [`when`](@ref when)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ track
    b(a) => a + 1 ~ capture
    c(a) => a + 1 ~ accumulate
end

simulate(S; stop=2)
```
\

#### [`integrate`](@id integrate)

`integrate` variables calculate an integral over a non-time variable using the Gaussian method.

Supported tags: [`unit`](@ref unit), [`from`](@ref from), [`to`](@ref to)

**Example**
```@example Cropbox
@system S(Controller) begin
    w => 1 ~ preserve(parameter)
    a => 0 ~ preserve(parameter)
    b => π ~ preserve(parameter)
    f(w; x) => w*sin(x) ~ integrate(from=a, to=b)
end

instance(S)
```
\

#### [`advance`](@id advance)

`advance` variables update an internal time-keeping variable. By default, it starts at 0 and increases by 1 every time step. Note that the unit does not have to be time-related.

Supported tags: [`init`](@ref init), [`step`](@ref step), [`unit`](@ref unit)

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ advance(init=1)
    b ~ advance(step=2)
    c ~ advance(u"m")
end

simulate(S; stop=2)
```
\

### *Data source*

#### [`provide`](@id provide)

`provide` variables provide a DataFrame with a given index (`index`) starting from an initial value (`init`). By default, `autounit` is `true`, meaning that `provide` variables will attempt to get units from column names.

Supported tags: [`index`](@ref index), [`init`](@ref init), [`step`](@ref step), [`autounit`](@ref autounit), [`parameter`](@ref parameter)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => DataFrame("index (hr)" => 0:2, "value (m)" => 0:10:20) ~ provide
end

instance(S).a
```
\

#### [`drive`](@id drive)

`drive` variables fetch the current value from a time-series. It is often used in conjunction with `provide`.

Supported tags: [`tick`](@ref tick), [`unit`](@ref unit), [`from`](@ref from), [`by`](@ref by), [`parameter`](@ref parameter), [`override`](@ref override)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => [2, 4, 6] ~ drive
end

simulate(S; stop=2)
```
\

#### [`tabulate`](@id tabulate)

`tabulate` variables make a two dimensional table with named keys. The `rows` tag must be assigned.

Supported tags: [`unit`](@ref unit), [`rows`](@ref rows), [`columns`](@ref columns), [`parameter`](@ref parameter)

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

instance(S)
```
\

#### [`interpolate`](@id interpolate)

`interpolate` variables make a curve function for a provided set of discrete values.

Supported tags: [`unit`](@ref unit), [`knotunit`](@ref knotunit), [`reverse`](@ref reverse), [`parameter`](@ref parameter)

**Example**
```@example Cropbox
@system S(Controller) begin
    m => [1 => 10, 2 => 20, 3 => 30] ~ interpolate
    a(m) => m(2.5) ~ track
end

instance(S)
```

A matrix can also be used instead of a vector of pairs.

```@example Cropbox
@system S(Controller) begin
    m => [1 10; 2 20; 3 30] ~ interpolate
    a(m) => m(2.5) ~ track
end

instance(S)
```
\

### *Equation solving*

#### [`solve`](@id solve)

`solve` variables solve a polynomial equation symbolically. By default, it will return the highest solution. Therefore, when using the `lower` tag, it is recommended to pair it with another tag.

Supported tags: [`unit`](@ref unit), [`lower`](@ref lower), [`upper`](@ref upper), [`pick`](@ref pick)

**Example**

*The solution is x = 1, 2, 3*

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve(parameter)
    b => -6 ~ preserve(parameter)
    c => 11 ~ preserve(parameter)
    d => -6 ~ preserve(parameter)
    x(a, b, c, d) => begin
        a*x^3 + b*x^2 + c*x + d
    end ~ solve
end

instance(S)
```
\

#### [`bisect`](@id bisect)

`bisect` variables solve a nonlinear equation using the bisection method. The tags `lower` and `upper` must be provided.

Supported tags: [`unit`](@ref unit), [`evalunit`](@ref evalunit), [`lower`](@ref lower), [`upper`](@ref upper), [`maxiter`](@ref maxiter), [`tol`](@ref tol), [`min`](@ref min), [`max`](@ref max)

**Example**

The solution is x = 1, 2, 3

```@example Cropbox
@system S(Controller) begin
    x(x) => x^3 - 6x^2 + 11x - 6 ~ bisect(lower=0, upper=3)
end

instance(S)
```
\

### *Dynamic structure*

#### [`produce`](@id produce)

`produce` variables attach a new instance of a dynamically generated system.

Supported tags: [`single`](@ref single), [`when`](@ref when)

**Example**
```@example Cropbox
@system S begin
    a => produce(S) ~ produce
end

@system SController(Controller) begin
    s(context) ~ ::S
end

instance(SController)
```
\

### *Language extension*

#### `hold`

`hold` variables are placeholders for variables that are supplied by another system as a mixin.

Supported tags: None

**Example**
```@example Cropbox
@system S1 begin
    a ~ advance
end

@system S2(S1, Controller) begin
    a ~ hold
    b(a) => 2*a ~ track
end

simulate(S2; stop=2)
```
\

#### `wrap`

`wrap` allows passing a reference to the state variable object, not a dereferenced value

Supported tags: None

**Example**
```@example Cropbox
@system S(Controller) begin
    a          => 1       ~ preserve 
    b(a)       => a == a' ~ flag
    c(wrap(a)) => a == a' ~ flag
end

instance(S)
```
\

#### [`call`](@id call)

`call` defines a partial function accepting user-defined arguments

Supported tags: [`unit`](@ref unit)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve
    f(a; x) => a + x ~ call
    b(f) => f(1) ~ track
end

instance(S)
```
\

#### [`bring`](@id bring)

`bring` duplicates variable declaration from another system into the current system

Supported tags: [`parameters`](@ref parameters), [`override`](@ref override)

**Example**
```@example Cropbox
@system S1 begin
    a => 1 ~ preserve
    b(a) => 2a ~ track
end

@system S2(Controller) begin
    c(context) ~ bring::S1
end

instance(S2)
```
\

## Variable Tags

Most variable states have tags in the form of `(tag)` for tag-specific behaviors. Available tags vary between variable states. Some tags are shared by multiple variable states while some tags are exclusive to certain variable states.

### [`autounit`](@id autounit)

Allows `provide` variables to automatically assign units to variables depending on column headers of the DataFrame. By default, `autounit` is `true` and only needs to be specified when `false`.

Used by: [`provide`](@ref provide)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => DataFrame("index" => (0:2)u"hr", "value (m)" => 0:10:20) ~ provide
    b => DataFrame("index" => (0:2)u"hr", "value (m)" => 0:10:20) ~ provide(autounit=false)
end
```
```@example Cropbox
instance(S).a
```
```@example Cropbox
instance(S).b
```
\

### [`by`](@id by)

Specifies the column and series from which the `drive` variable receives data. Can be omitted if the variable name is identical to column name.

Used by: [`drive`](@ref drive)

**Example**
```@example Cropbox
@system S(Controller) begin
    p => DataFrame(index=(0:2)u"hr", a=[2,4,6], x=1:3) ~ provide
    a ~ drive(from=p)
    b ~ drive(from=p, by=:x)
end

simulate(S; stop=2)
```
\

### [`columns`](@id columns)

Specifies the names of columns from the table created by the `tabulate` variable.

Used by: [`tabulate`](@ref tabulate)

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

instance(S).T
```
\

### [`evalunit`](@id evalunit)

Specifies the evaluation unit of `bisect`, as opposed to the unit of solution.

Used by: [`bisect`](@ref bisect)

**Example**
```@example Cropbox
@system S(Controller) begin
    f(x) => (x/1u"s" - 1u"m/s") ~ track(u"m/s")
    x(f) ~ bisect(lower=0, upper=2, u"m", evalunit=u"m/s")
end

instance(S)
```
\

### [`extern`](@id extern)

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`flag`](@ref flag)

### [`from`](@id from)

`drive`: Specifies the DataFrame that the `drive` variable will receive data from. If the variable name of the `drive` variable differs from column name, `from` must be accompanied with `by`.

`integrate`: Specifies lower bound of integration.

Used by: [`drive`](@ref drive), [`integrate`](@ref integrate)

**Example**: `drive`
```@example Cropbox
@system S(Controller) begin
    p => DataFrame(index=(0:2)u"hr", a=[2,4,6], x=1:3) ~ provide
    a ~ drive(from=p)
    b ~ drive(from=p, by=:x)
end

simulate(S; stop=2)
```
\

**Example**: `integrate`
```@example Cropbox
@system S(Controller) begin
    w => 1 ~ preserve(parameter)
    a => 0 ~ preserve(parameter)
    b => π ~ preserve(parameter)
    f(w; x) => w*sin(x) ~ integrate(from=a, to=b)
end

instance(S)
```
\

### [`index`](@id index)

Used by `provide` variables to specify the index column from provided DataFrame. Can be omitted if DataFrame contains column "index".

Used by: [`provide`](@ref provide)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => DataFrame(i=(0:3)u"hr", value=0:10:30) ~ provide(index=:i)
end
        
instance(S)
```
\

### [`init`](@id init)

Assigns the first value of the variable at system instantiation.

Used by: [`track`](@ref track), [`remember`](@ref remember), [`accumulate`](@ref accumulate), [`advance`](@ref advance), [`provide`](@ref provide)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ accumulate(init=100)
end

simulate(S; stop=2)
```
\

### [`knotunit`](@id knotunit)

Specifies the unit of discrete x-values of `interpolate`.

Used by: [`interpolate`](@ref interpolate)

**Example**
```@example Cropbox
@system S(Controller) begin
    m => ([1 => 10, 2 => 20, 3 => 30]) ~ interpolate(u"s", knotunit=u"m")
    n(m) ~ interpolate(u"m", reverse)
    a(m) => m(2.5u"m") ~ track(u"s")
    b(n) => n(25u"s") ~ track(u"m")
end

instance(S)
```
\

### [`lower`](@id lower)

Specifies the lower bound of the solution for `solve` and `bisect` variables.

Used by: [`solve`](@ref solve), [`bisect`](@ref bisect)

**Example**

*The solution is x = 1, 2, 3*

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve(parameter)
    b => -6 ~ preserve(parameter)
    c => 11 ~ preserve(parameter)
    d => -6 ~ preserve(parameter)
    x(a, b, c, d) => begin
        a*x^3 + b*x^2 + c*x + d
    end ~ solve(lower=1.1, upper=2.9)
end

instance(S)
```
\

### [`max`](@id max)

Defines the maximum value of the variable.

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`accumulate`](@ref accumulate), [`bisect`](@ref bisect)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ accumulate(max=1)
end

simulate(S; stop=2)
```
\

### [`maxiter`](@id maxiter)

Defines the maximum number of iterations for the `bisect`.

Used by: [`bisect`](@ref bisect)

**Example**
```@example Cropbox
@system S(Controller) begin
    x(x) => x - 0.25 ~ bisect(lower=0, upper=1, maxiter=4)
end

instance(S)
```
\

### [`min`](@id min)

Defines the minimum value of the variable.

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`accumulate`](@ref accumulate), [`bisect`](@ref bisect)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => -1 ~ accumulate(min=-1)
end

simulate(S; stop=2)
```
\

### [`once`](@id once)

Makes a `flag` variable unable to go from `true` to `false`.

Used by: [`flag`](@ref flag)

**Example**
```@example Cropbox
@system S(Controller)begin
    a ~ advance(init=1)
    f(a) => (a % 2 == 0) ~ flag(once)
end

simulate(S; stop=2)
```
\

### [`optional`](@id optional)

Makes a `preserve` variable optional, allowing a system to be instantiated without variable assignment.

Used by: [`preserve`](@ref preserve)

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ preserve(optional, parameter)
    b => 1 ~ preserve
end

simulate(S; stop=2)
```
\

### [`override`](@id override)

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`flag`](@ref flag), [`drive`](@ref drive), [bring](@ref bring)

**Example**
```@example Cropbox
@system S1 begin
    a ~ track(override)
end

@system S2(Controller) begin
    c(context, a) ~ ::S1
    a => 1 ~ track
end

instance(S2)
```
\

### [`parameter`](@id parameter)

Allows the variable to be altered through a configuration at system instantiation.

Used by: [`preserve`](@ref preserve), [`flag`](@ref flag), [`provide`](@ref provide), [`drive`](@ref drive), [`tabulate`](@ref tabulate), [`interpolate`](@ref interpolate)

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ preserve(parameter)
end

instance(S; config = :S => :a => 1)
```
\

### [`parameters`](@id parameters)

Use by `bring` variables to duplicate only variables that *can* have the `parameter` tag (if they did not have the `parameter` tag originally, they become parameters regardless). The duplicated variables must have their values reassigned through a configuration.

Used by: [`bring`](@ref bring)

**Example**
```@example Cropbox
@system S1 begin
    a => 1 ~ preserve
    b(a) => 2a ~ track
    c => true ~ flag

    d(a) ~ accumulate
end

@system S2(Controller) begin
    p(context) ~ bring::S1(parameters)
end

instance(S2; config = :S2 => (:a => 2, :b => 3, :c => false))
```
\

### [`pick`](@id pick)

Picks which solution to return based on tag argument. 

Used by: [`solve`](@ref solve)

**Example**

*The solution is x = 1, 2, 3*

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve(parameter)
    b => -3 ~ preserve(parameter)
    c => 2 ~ preserve(parameter)
    x(a, b, c) => begin
        a*x^2 + b*x + c
    end ~ solve(pick=:minimum)
end

instance(S)
```
\

### [`ref`](@id ref)

Used by: [`preserve`](@ref preserve), [`track`](@ref track)

### [`reset`](@id reset)

Resets the sum to 0 at every time step.

Used by: [`accumulate`](@ref accumulate)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ accumulate(reset)
end

simulate(S; stop=2)
```
\

### [`reverse`](@id reverse)

Returns the inverse function of an existing `interpolate` variable.

Used by: [`interpolate`](@ref interpolate)

**Example**
```@example Cropbox
@system S(Controller) begin
    m => ([1 => 10, 2 => 20, 3 => 30]) ~ interpolate
    n(m) ~ interpolate(reverse)
    a(m) => m(2.5) ~ preserve
    b(n) => n(25) ~ preserve
end

instance(S)
```
\

### [`round`](@id round)

Rounds to the nearest integer or to a floor or ceiling based on tag argument.

Used by: [`preserve`](@ref preserve), [`track`](@ref track)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1.4 ~ preserve(round)
    b => 1.4 ~ preserve(round=:round)
    c => 1.4 ~ preserve(round=:ceil)
    d => 1.6 ~ preserve(round=:floor)
    e => 1.6 ~ preserve(round=:trunc) 
end

instance(S)
```
\

### [`rows`](@id rows)

Specifies the names of rows from the table created by the `tabulate` variable. Required tag for `tabulate`.

Used by: [`tabulate`](@ref tabulate)

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
\

### [`single`](@id single)

Used by: [`produce`](@ref produce)

### [`skip`](@id skip)

Used by: [`track`](@ref track)

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ advance
    b(a) => 2*a ~ track(skip=true)
end

simulate(S; stop=2)
```
\

### [`step`](@id step)

`advance`: Specifies the increments of the `advance` variable.

`provide`: Specifies the intervals of the index column.

Used by: [`advance`](@ref advance), [`provide`](@ref provide)

**Example:** `advance`
```@example Cropbox
@system S(Controller) begin
    a ~ advance
    b ~ advance(step=2)
    c ~ advance(step=-1)
end

simulate(S; stop=2)
```
\

**Example:** `integrate`
```@example Cropbox
@system S(Controller) begin
    a => DataFrame("index (hr)" => 0:4, "value (m)" => 0:10:40) ~ provide(step=2u"hr")
end

instance(S).a
```
\

### [`tick`](@id tick)

Used by: [`drive`](@ref drive)

### [`time`](@id time)

Accumulates variable at a specified rate of time.

Used by: [`accumulate`](@ref accumulate), [`capture`](@ref capture)

**Example**
```@example Cropbox
@system S(Controller) begin
    t(x=context.clock.time) => 0.5x ~ track(u"hr")
    a => 1 ~ accumulate
    b => 1 ~ accumulate(time=t)
end

simulate(S; stop=5)
```
\

### [`timeunit`](@id timeunit)

Specifies the time unit of the variable.

Used by: [`accumulate`](@ref accumulate), [`capture`](@ref capture)

**Example**
```@example Cropbox
@system S(Controller) begin
    a => 1 ~ accumulate(timeunit=u"d")
end

simulate(S; stop=2)
```
\

### [`to`](@id to)

Specifies upper bound of integration.

Used by: [`integrate`](@ref integrate)

**Example**
```@example Cropbox
@system S(Controller) begin
    w => 1 ~ preserve(parameter)
    a => 0 ~ preserve(parameter)
    b => π ~ preserve(parameter)
    f(w; x) => w*sin(x) ~ integrate(from=a, to=b)
end

instance(S)
```
\

### [`tol`](@id tol)

Defines the tolerance for the bisection method used in `bisect`.

Used by: [`bisect`](@ref bisect)

**Example**
```@example Cropbox
@system S(Controller) begin
    x(x) => x - 2.7 ~ bisect(lower=1, upper=3)
    y(y) => y - 2.7 ~ bisect(lower=1, upper=3, tol=0.05)
end

instance(S)
```
\

### [`unit`](@id unit)

Specifies the unit of the variable. The tag `unit` can be omitted.

Used by: [`preserve`](@ref preserve), [`track`](@ref track), [`remember`](@ref remember), [`accumulate`](@ref accumulate), [`capture`](@ref capture), [`integrate`](@ref integrate), [`advance`](@ref advance), [`drive`](@ref drive), [`tabulate`](@ref tabulate), [`interpolate`](@ref interpolate), [`solve`](@ref solve), [`bisect`](@ref bisect), [`call`](@ref call)

```example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve(unit=u"hr")
    b => 1 ~ preserve(u"hr")
end

instance(S)
```
\

### [`upper`](@id upper)

Specifies the upper bound of solution.

Used by: [`solve`](@ref solve), [`bisect`](@ref bisect)

**Example**

*The solution is x = 1, 2, 3*

```@example Cropbox
@system S(Controller) begin
    a => 1 ~ preserve(parameter)
    b => -6 ~ preserve(parameter)
    c => 11 ~ preserve(parameter)
    d => -6 ~ preserve(parameter)
    x(a, b, c, d) => begin
        a*x^3 + b*x^2 + c*x + d
    end ~ solve(upper=2.9)
end

instance(S)
```
\

### [`when`](@id when)

Specifies when a variable should be evaluated. It is supplied with a `flag` variable, and the specified variable is evaluated when the `flag` variable is `true`.

Used by: [`track`](@ref track), [`flag`](@ref flag), [`remember`](@ref remember), [`accumulate`](@ref accumulate), [`capture`](@ref capture), [`produce`](@ref produce)

**Example**
```@example Cropbox
@system S(Controller) begin
    a ~ advance
    flag(a) => (a >= 2) ~ flag
    b(a) => a ~ track(when=flag)
end

simulate(S; stop=3u"hr")
```
