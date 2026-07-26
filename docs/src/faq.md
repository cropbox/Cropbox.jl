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

Degrees Celsius is an affine temperature scale. A temperature difference has
kelvin dimensions. Declare absolute temperatures with `u"°C"` and differences
or thermal-time rates with `u"K"`, `u"K/d"`, or `u"K*d"` as appropriate.

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

## Should I use experimental `fixedpoint` because it is faster?

Only after verifying convergence and accuracy over the entire input domain. A
fixed-point iteration depends on the chosen formulation, initial value,
damping, and clipping; it has weaker general convergence guarantees than a
properly bracketed bisection. Keep a trusted reference path for comparison.

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
consume it. Cropbox's `plot` and `visualize` are conveniences, not a required
storage format.

## Where should a question be documented?

- declaration grammar or tag compatibility: [DSL Syntax](@ref dsl-syntax) and
  [Behaviors and Tags](@ref behaviors-and-tags);
- configuration recipes:
  [Configure Models and Scenarios](@ref configuration-workflow);
- simulation and output recipes:
  [Run Simulations and Shape Output](@ref simulation-workflow);
- a model package's biological parameters: that model's own documentation.
