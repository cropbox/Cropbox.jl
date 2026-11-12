# [Sensitivity Analysis](@id sensitivity-workflow)

Sensitivity analysis asks which parameter changes matter for a chosen model
output. It is separate from [evaluation and calibration](@ref
evaluation-tutorial): a sensitive parameter is not necessarily well constrained
by observations.

This guide uses the same logistic growth equation as the [Quick Start](@ref
quick-start). The question is: how do the specified ranges of growth rate and
final biomass affect biomass after 200 days?

## Define the model and parameter ranges

```@example sensitivityflow
using Cropbox
using GlobalSensitivity
using Random

@system LogisticGrowth(Controller) begin
    r: growth_rate       => 0.05                 ~ preserve(parameter, u"d^-1")
    Wf: final_biomass    => 300                  ~ preserve(parameter, u"g")
    W0: initial_biomass  => 0.25                 ~ preserve(parameter, u"g")

    W(W, r, Wf): biomass => r * W * (1 - W / Wf) ~ accumulate(init = W0, u"g")
end

bounds = LogisticGrowth => (
    r  = (0.03, 0.07),
    Wf = (200, 400),
)
nothing # hide
```

The bounds use each parameter's declared unit. They define the comparison:
changing these ranges can change the apparent importance of a parameter.

## Run the analysis

```@example sensitivityflow
result = analyze(LogisticGrowth;
    config = Clock => :step => 1u"d",
    stop = 200u"d",
    target = :W,
    parameters = bounds,
    method = Morris(num_trajectory = 20),
    gsa = (; rng = Xoshiro(42)),
)

visualize(result.table, :means_star, :parameter;
    xlab = "Mean absolute effect",
    ylab = "Parameter",
    ycat = result.table.parameter,
    legend = false,
)
```

`analyze` samples parameter combinations and runs the model. This form reads
the final `W`; `means_star` summarizes the magnitude of Morris effects across
the chosen ranges. The effect has the output unit, grams. It is not a response
to the same physical increment of each parameter.

Read `result.table` to inspect the numerical results. This small screening
example is not a demonstration of sampling convergence or biological validity.
Use more trajectories and compare results before drawing a substantive
conclusion about a model.

## Choose the next question

- Change the horizon to ask whether the important parameters differ early and
  late in growth.
- Use a callback when the output of interest summarizes a whole trajectory.
- Use separate conditions when comparing environments instead of averaging
  their outputs.

The [Sensitivity Analysis API](@ref sensitivity-analysis) gives executable
examples for callbacks, multiple conditions, Morris, Sobol, and eFAST, along
with every supported option, returned field, unit rule, and current limitation.
