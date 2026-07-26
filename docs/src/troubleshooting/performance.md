# [Performance and Reproducibility](@id performance-guide)

Cropbox performance is a combination of Julia compilation, model construction,
update equations, solver work, output extraction, and downstream visualization.
Measure those parts separately before changing a model.

## Start with a representative workload

Define what matters:

- latency of one interactive run;
- throughput across many configurations;
- memory for a long time series;
- cost of a nonlinear solver at each step;
- traversal and export of dynamic geometry;
- calibration across environments.

An optimization for one workload may make another worse or less reproducible.

## Separate compilation from runtime

Julia compiles methods on first use. Warm up the model with a small valid run,
then time repeated execution.

```julia
simulate(Model; config, stop = 1u"d", target = :output, verbose = false)

@time simulate(Model;
    config,
    stop = 100u"d",
    target = :output,
    verbose = false,
)
```

For rigorous benchmarking, use an appropriate benchmarking tool in the analysis
environment. The manual avoids adding one as a documentation dependency.

## Reduce output before changing equations

Output often dominates a large run.

1. specify only required `target` columns;
2. increase the `snap` interval;
3. avoid wildcard and recursive structure extraction;
4. request `long=true` only when needed;
5. disable progress output inside repeated loops;
6. write large geometry only at selected dates.

`nounit=true` removes units while formatting returned columns. It does not remove
unit operations from model execution and should not be treated as a general
solver optimization.

## Choose the model time step scientifically

A coarser `Clock.step` performs fewer updates but changes numerical integration
and event timing. Demonstrate convergence of the scientific result as the time
step is refined. Keep `snap` independent: output can be sparse even when updates
must be fine.

## Batch configurations deliberately

Cropbox can run multiple configurations on Julia threads. This is useful for
sensitivity analysis and calibration, but it adds requirements:

- callbacks must not mutate shared global state;
- external resources in `options` must be independent or thread-safe;
- random seeds must express the intended comparison;
- each scenario's metadata must be retained;
- nested libraries should not oversubscribe threads unexpectedly.

Benchmark a batch representative of the real number and duration of scenarios,
not only one instance.

## Reuse only when continuation is intended

`simulate!` can avoid reconstruction, but it advances mutable state. Reuse is
correct for staged management or for exporting a final structure. It is not
correct for independent scenarios. If construction is expensive, first measure
whether it is actually significant relative to the update loop.

## Solver-intensive models

For LeafGasExchange and other coupled models:

- measure the number of solver calls and iterations;
- identify the environmental region causing worst-case convergence;
- check residual brackets and units;
- keep a trusted reference formulation;
- compare both outputs and failure rates over a grid;
- report tolerance and iteration limits with timing results.

Experimental fixed-point or analytical paths can be faster for a particular
formulation, but the framework-level conclusion must not be inferred from one
model's algorithmic change.

## Whole-plant and integration-heavy models

In Garlic, costs may come from radiation integration, coupled gas exchange,
instance construction, dynamic organs, aggregation, and output together. Profile
the full run before optimizing one numerical integral. Preserve agreement in
leaf area, phenology, carbon balance, and final mass, not only one intermediate
rate.

## Dynamic root architecture

For CropRootBox:

- reduce branching depth and spatial resolution during development;
- collect root summaries at coarse intervals;
- traverse the architecture once per snapshot rather than once per metric;
- defer VTK, STL, or rendering until chosen dates;
- measure file I/O separately from simulation;
- retain configuration and seed beside every export.

The number of dynamic systems can grow rapidly, so a short simulation may not
predict later memory or traversal cost.

## Calibration

Calibration multiplies every model cost by many candidates and environments.

- validate one candidate outside the optimizer first;
- start with a small `MaxSteps` budget;
- restrict the fitted parameter set;
- use explicit targets and observation snapshots;
- separate training and validation data;
- record Cropbox's fixed calibration seed behavior and set stochastic model
  seeds explicitly;
- retain optimizer options and package versions.

If each objective evaluation is expensive, optimize the simulation and output
layout before increasing the optimizer budget.

## Reproducibility checklist

Record:

- Julia, Cropbox, and model package versions;
- complete base configuration and treatment patches;
- input data identity and preprocessing;
- time zone, calendar initialization, and `Clock.step`;
- stop and snapshot rules;
- output layout and units;
- random seed per replicate;
- solver tolerances and iteration limits;
- calibration metric, bounds, weights, and optimizer options;
- hardware and Julia thread count for performance results.

Performance without this context is difficult to reproduce and can encourage
changes that alter the scientific problem.
