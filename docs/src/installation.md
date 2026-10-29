# [Installation](@id Installation)

The simplest setup is Julia plus the registered Cropbox package. Docker and
Jupyter are alternatives when a local Julia installation is inconvenient or a
notebook interface is preferred. A separate Julia package is useful later,
when a model becomes a maintained project.

## 1. Install Cropbox locally

Install Julia using the
[official Juliaup-based instructions](https://docs.julialang.org/en/v1/manual/installation/),
then start Julia and add Cropbox:

```julia
using Pkg
Pkg.add("Cropbox")

using Cropbox
```

This installs the current registered Cropbox release in Julia's active
environment. It is enough for the [Quick Start](@ref quick-start); no document
builder, editor extension, or notebook package is required.

The first `using Cropbox` may take longer while Julia compiles packages. Later
sessions reuse the compilation cache.

## 2. Use Docker

The [`cropbox/cropbox` image](https://hub.docker.com/r/cropbox/cropbox) includes
Julia, Cropbox, Jupyter, and commonly used model packages. With Docker running:

```shell
docker run --rm -it -p 8888:8888 cropbox/cropbox
```

Open the Jupyter URL printed in the terminal. Files created only inside the
container disappear when it stops, so mount a working directory when results
must be retained:

```shell
docker run --rm -it -p 8888:8888 -v "$PWD":/home/jovyan/work cropbox/cropbox
```

With no explicit tag, Docker uses the released `latest` image. The `main` tag
follows current development and may change without notice; use a versioned tag
or an image digest when an analysis must be exactly reproducible.

A hosted
[Cropbox Binder session](https://mybinder.org/v2/gh/cropbox/cropbox-binder/main)
is convenient for a short trial without installing Julia or Docker. Its startup
time, storage, and session lifetime are controlled by Binder.

## 3. Work in Jupyter

IJulia connects a local Julia installation to Jupyter Notebook and JupyterLab:

```julia
using Pkg
Pkg.add("Cropbox")
Pkg.add("IJulia")

using IJulia
notebook()
```

The first `notebook()` call can install a private Jupyter distribution if one
is not already available. If Jupyter is already installed, adding IJulia also
registers a Julia kernel that can be selected from that interface. The Docker
image in the preceding section already starts with this integration available.

## 4. Use a project environment

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

## 5. Develop a model as a Julia package

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

`Pkg.develop(path="/path/to/Cropbox.jl")` is a separate, advanced workflow for
editing Cropbox itself or testing against an unreleased local checkout. Normal
model development should use `Pkg.add("Cropbox")`.

## Add model packages as needed

LeafGasExchange, Garlic, SimpleCrop, and CropRootBox are separate registered
packages. Add only the model used by the analysis:

```julia
using Pkg
Pkg.add("LeafGasExchange")
Pkg.add("Garlic")
Pkg.add("SimpleCrop")
Pkg.add("CropRootBox")
```

For an unregistered model or a specific revision:

```julia
using Pkg
Pkg.add(url="https://github.com/organization/Model.jl", rev="main")
```

Record the repository revision or commit with a published analysis. Continue
with the [Quick Start](@ref quick-start).
