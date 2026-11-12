# [Projects and Model Packages](@id model-projects)

The [installation page](@ref Installation) is enough to run a first model.
Use a project environment when an analysis needs reproducible dependencies,
and a Julia package when model code will be reused or shared.

## Use a project environment

Once an analysis has more than a few exploratory cells, give it an isolated
environment:

```shell
mkdir my-cropbox-analysis
cd my-cropbox-analysis
julia --project=.
```

At the Julia prompt:

```julia
using Pkg
Pkg.add("Cropbox")
```

This creates `Project.toml` and `Manifest.toml` in the directory. Keep both
files with a reproducible analysis so package versions can be restored later.
The same environment can be selected by a Julia script, VS Code, or an IJulia
kernel.

In a notebook, activate the same project before loading Cropbox or a model:

```julia
using Pkg
Pkg.activate("/path/to/my-cropbox-analysis")
using Cropbox
Base.active_project()
```

Replace the path with the directory created above. The last line should point
to its `Project.toml`. Restart the kernel first if another version of Cropbox
has already been loaded in that session.

## Develop a model as a Julia package

Use a package when the model has reusable source files, tests, or collaborators.
Julia's built-in package manager creates the minimal structure:

```julia
using Pkg
Pkg.generate("MyCropModel")
Pkg.activate("MyCropModel")
Pkg.add("Cropbox")
```

Put systems in `MyCropModel/src/MyCropModel.jl`, export the model types meant
for users, and add focused examples or tests under `test/`. A minimal package
module starts like this:

```julia
module MyCropModel

using Cropbox

@system Model(Controller) begin
    rate => 1  ~ preserve(parameter, u"g/d")
    mass(rate) ~ accumulate(u"g")
end

export Model

end
```

Run Julia from the package directory with `julia --project=.`. This is the
appropriate place for source control, a committed environment, data-loading
helpers, and automated tests.

From that environment, check that the package loads and runs:

```julia
using Cropbox
using MyCropModel

simulate(MyCropModel.Model;
    config = Clock => :step => 1u"d",
    stop = 2u"d",
    target = :mass,
)
```

The result includes the initial state and two daily updates, with `mass` equal
to 0, 1, and 2 grams.

`Pkg.develop(path="/path/to/Cropbox.jl")` is a separate, advanced workflow for
editing Cropbox itself or testing against an unreleased local checkout. Normal
model development should use `Pkg.add("Cropbox")`.

## Add model packages as needed

LeafGasExchange, Garlic, SimpleCrop, and CropRootBox are separate registered
packages. Add only the model used by the analysis; for example:

```julia
using Pkg
Pkg.add("LeafGasExchange")
```

For another tutorial, replace `"LeafGasExchange"` with `"Garlic"`,
`"SimpleCrop"`, or `"CropRootBox"`. Each tutorial lists any additional packages
needed for its tables, input files, or exports.

For an unregistered model or a specific revision:

```julia
using Pkg
Pkg.add(url="https://github.com/organization/Model.jl", rev="main")
```

Record the repository revision or commit with a published analysis. Use
[Configure Models and Scenarios](@ref configuration-workflow) to organize runs,
or choose a model study from the [Learning Path](@ref learning-path).
