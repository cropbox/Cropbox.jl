# [Installation](@id Installation)

Cropbox is a Julia package. A local Julia installation and a small project
environment are enough; the documentation does not require a separate site
generator or notebook stack.

## Install Julia

For a new installation, use [Juliaup](https://github.com/JuliaLang/juliaup),
the version manager recommended by the Julia project. Follow the
[official installation instructions](https://docs.julialang.org/en/v1/manual/installation/)
for your platform. Juliaup keeps Julia versions up to date and makes it easy to
retain an older version for a project that needs one.

Verify the installation in a terminal:

```shell
julia --version
```

## Create a project and install Cropbox

Keeping each model in its own Julia environment makes examples reproducible and
prevents unrelated package updates from changing a working model.

```shell
mkdir my-cropbox-model
cd my-cropbox-model
julia --project=.
```

At the Julia prompt, activate the directory and install Cropbox:

```julia
using Pkg
Pkg.activate(".")
Pkg.add("Cropbox")

using Cropbox
```

The first import may take longer while Julia compiles the package. Later imports
reuse the compilation cache. Commit both `Project.toml` and `Manifest.toml` when
the exact package versions must be reproducible.

To work from a local checkout of Cropbox itself, use `Pkg.develop` from the model
environment:

```julia
using Pkg
Pkg.develop(path="/path/to/Cropbox.jl")
```

## Choose an editor

Cropbox works in the Julia REPL, scripts, and notebooks. The
[Julia extension for Visual Studio Code](https://www.julia-vscode.org/) is a
good default for scripts and packages. For Jupyter notebooks, add IJulia to the
project in which the notebooks will run:

```julia
using Pkg
Pkg.add("IJulia")
```

An editor or notebook is optional; neither is a Cropbox dependency.

## Install model packages used in the tutorials

The LeafGasExchange, Garlic, and CropRootBox tutorials use separate packages.
They are available through Julia's
[General registry](https://github.com/JuliaRegistries/General), but they are not
dependencies of this manual. Add only the model you need to the same project
environment:

```julia
using Pkg
Pkg.add("LeafGasExchange")
Pkg.add("Garlic")
Pkg.add("CropRootBox")
```

SimpleCrop can likewise be installed with `Pkg.add("SimpleCrop")`. Each
tutorial gives its exact setup command.

For an unregistered model package or a specific development revision, provide
its repository URL and, when needed, a revision:

```julia
using Pkg
Pkg.add(url="https://github.com/organization/Model.jl", rev="main")
```

Use `Pkg.develop(url="...")` instead when you intend to edit that package
locally. Record the repository revision or commit alongside a published model
analysis.

## Docker and Binder

The [`cropbox/cropbox` Docker image](https://hub.docker.com/r/cropbox/cropbox)
can provide an isolated notebook environment:

```shell
docker run -it --rm -p 8888:8888 cropbox/cropbox
```

Open the URL printed by JupyterLab. Check the image tag and package versions
before using the container for a reproducible analysis; a local Julia project
with a committed manifest gives finer version control.

A hosted [Binder environment](https://mybinder.org/v2/gh/cropbox/cropbox-binder/main)
is useful for a short trial, but startup time and session lifetime are outside
Cropbox's control.

Continue with the [Quick Start](@ref quick-start).
