# [Frequently Asked Questions](@id faq)

## Why does `simulate` include a row at time zero?

`instance` performs initial construction and update, and the default snapshot
rule saves that initialized state before advancing. The row is an initial
condition, not an extra model day. Filter it only when the analysis explicitly
requires post-update values.

## Why did the model stop one step later than expected?

Cropbox checks a Boolean stop condition at discrete update boundaries. A daily
model cannot stop at the exact instant a continuous threshold was crossed
within a day. Reduce `Clock.step` if sub-step timing matters, or record the
crossing with a model variable designed for interpolation.

A duration such as `stop=25u"hr"` is converted to a whole number of updates. If
`Clock.step` is not an exact divisor, Cropbox rounds the update count up. Choose
compatible values when the final clock time must match the requested duration.

## Why is my result empty after adding `snap`?

`snap` controls collection, not updates. The condition may never be true at an
update boundary, may use the wrong unit or time zone, or may become true only
after `stop` terminates the model. Test the condition on a short run with a
broader snapshot rule and include its source variables in `target`.

## Why is a configuration value ignored?

Check these in order:

1. the declaration has the `parameter` tag;
2. the configuration uses the declaring system's key;
3. it uses the short name or recognized alias;
4. a later configuration is not overriding it;
5. a nested system is actually present in the selected model variant.

Use `parameters(Model; alias=true, recursive=true)` and inspect the constructed
instance with `parameters(s; recursive=true)`.

## What is the difference between `config`, `configs`, and `parameters` in `simulate`?

- `config` is one scenario or a base applied to a sweep.
- `configs` is a vector of complete or partial scenarios, one fresh instance per
  entry.
- `parameters` is a convenience sweep used by interactive manipulation and
  automatically adds identifying metadata.

For reproducible studies, explicit `@config` expansion plus `configs` is usually
the clearest choice. Do not supply both nonempty `configs` and `parameters`.

## When should I use `simulate!`?

Use it when you deliberately want to continue or externally inspect one existing
instance—for example, to export CropRootBox geometry after growth. It mutates the
instance. Use `simulate(Model; ...)` for fresh independent runs.

## Why does `s.variable` not behave like a number?

Most system fields are Cropbox state objects. Declared dependencies receive
their values automatically, but ordinary Julia code should use `s.variable'` or
`value(s.variable)`. `wrap` deliberately passes the state object and is not a
general value-access shortcut.

## How do I select a variable inside a nested system?

Use a string path or a renamed pair:

```julia
simulate(Model;
    target = [
        "calendar.date",
        :sunlit_A => "sunlit_gasexchange.A_net",
    ],
)
```

`"child.*"` is helpful for exploration. Replace it with explicit paths in a
stable analysis because wildcard output changes when the model gains fields.

## Why is a non-scalar variable missing from default output?

Default extraction keeps simple values such as numbers, symbols, strings, and
date/time values. Vectors, tuples, dictionaries, dynamic systems, functions,
tables, meshes, and other structures are omitted even when named in `target`.
Declare an addressable scalar summary, or use `snatch`/a do-block to calculate
custom rows.

## Why does `dive` not work interactively in my notebook?

`dive` uses a terminal menu. In IJulia it falls back to noninteractive output.
Use `look`, `@look`, `parameters`, property access, or explicit path selection in
notebooks.

## How are numbers without units interpreted in configuration?

For a unitful parameter, Cropbox interprets a plain number in the declaration's
unit. `Clock => :step => 1` therefore means one clock unit, which is an hour for
the default clock. Prefer `1u"d"`, `30u"minute"`, and similarly explicit values
at system and package boundaries.

## Why did a temperature subtraction fail or produce kelvin?

Degrees Celsius is an affine temperature scale. Declare absolute temperatures
with `u"°C"`, temperature differences with `u"K"`, and accumulated thermal
time with a unit such as `u"K*d"`. A rate with unit `u"K/d"` needs a time
scale in its equation; subtracting two temperatures alone does not supply one.

## Why does clock output contain fractions or a rational-conversion warning?

The built-in clock stores exact rational times. A displayed `(1//6)u"hr"`
means exactly ten minutes, not a different model time. Time-step, stop, and
snapshot settings supplied as floating-point quantities are converted to
rational values with a warning. Use `1u"minute"` instead of `1.0u"minute"`, or
`6u"minute"` / `(1//10)u"hr"` instead of `0.1u"hr"`, to state the intended
interval directly.

`provide` can also warn when it converts a floating-point numeric time index
to match a rational clock. Check the resulting index and input coverage; this
conversion does not interpolate missing data. Ordinary model parameters and
state values do not need to be rewritten as fractions. See the
[subdaily simulation example](@ref simulation-workflow) for a complete run.

## Why did `provide` or `drive` fail near the end of a run?

The requested index may not exist in the input table, dates may be unsorted or
duplicated, or the calendar time zone may not match the data. Confirm that input
coverage extends through the stop date and inspect the provider's `index`,
`init`, `step`, and the driver's `from`/`by` tags.

## What does a bisection convergence failure mean?

The residual may not change sign between `lower` and `upper`, units may be
incompatible, or the model may be outside the solver's intended domain. Recreate
one failing input with `instance`, inspect the residual at both bounds, and
check upstream variables. Increasing `maxiter` cannot fix an unbracketed root.

## How do I make a stochastic model reproducible?

Pass `seed` to `instance` or `simulate` and retain it with the configuration.
Values written with `±` may be sampled during construction. In a batched
configuration run, the same seed is reset for each scenario; use explicit seed
loops for independent Monte Carlo replicates.

## Why is the first run much slower?

Julia compiles methods on first use. Run a small warm-up outside the timed
section, then measure construction, simulation, output collection, plotting, and
file export separately. See [Performance and Reproducibility](@ref
performance-guide).

## Can I use a different plotting package?

Yes. `simulate` returns a DataFrame, so any Julia or external plotting tool can
consume it. Cropbox's `visualize` is a convenience, not a required storage
format.

## Where should a question be documented?

- declaration grammar or tag compatibility: [DSL Syntax](@ref dsl-syntax) and
  [Behaviors and Tags](@ref behaviors-and-tags);
- configuration recipes:
  [Configure Models and Scenarios](@ref configuration-workflow);
- simulation and output recipes:
  [Run Simulations and Shape Output](@ref simulation-workflow);
- a model package's biological parameters: that model's own documentation.
