# Cropbox

Cropbox is a framework for building and running crop models in Julia. Describe
the variables and equations; Cropbox connects their dependencies, advances the
model, and collects its output.

A small growth model can be simulated and plotted in one call:

```@example home
using Cropbox

@system LogisticGrowth(Controller) begin
    r: growth_rate       => 0.05                 ~ preserve(parameter, u"d^-1")
    Wf: final_biomass    => 300                  ~ preserve(parameter, u"g")
    W0: initial_biomass  => 0.25                 ~ preserve(parameter, u"g")

    W(W, r, Wf): biomass => r * W * (1 - W / Wf) ~ accumulate(init = W0, u"g")
end

visualize(LogisticGrowth, :time, :W; stop = 200u"d", xunit = u"d", kind = :line)
```

Biomass starts small, grows more quickly, and approaches its final size.
The same specification → simulation → visualization and evaluation workflow
also applies to leaf gas exchange, whole-plant growth, soil water, and root
architecture.

## Start here

[Install Cropbox](@ref Installation), then follow the
[Quick Start](@ref quick-start) to run this model and compare growth scenarios.
The [Learning Path](@ref learning-path) continues with weather input and
interacting populations.

Already working on a model? Use the [guides](@ref configuration-workflow) for
specific tasks, or the [Reference](@ref reference-guide) for full syntax,
arguments, examples, and results. [Models and Resources](@ref Gallery) links
the larger applications, papers, and workshop material.

## Citation

When using Cropbox in your work, please cite the following paper:

Yun K, Kim S-H (2023) “Cropbox: a declarative crop modelling framework.”
*in silico Plants* 5(1), diac021.
[doi:10.1093/insilicoplants/diac021](https://doi.org/10.1093/insilicoplants/diac021)

```bibtex
@article{Cropbox2023,
    title = {Cropbox: a declarative crop modelling framework},
    author = {Yun, Kyungdahm and Kim, Soo-Hyung},
    journal = {in silico Plants},
    volume = {5},
    number = {1},
    year = {2023},
    doi = {10.1093/insilicoplants/diac021}
}
```

The repository also keeps this entry in
[`CITATION.bib`](https://github.com/cropbox/Cropbox.jl/blob/main/CITATION.bib).
