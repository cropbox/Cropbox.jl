# [Installation](@id Installation)

The simplest setup is Julia plus the registered Cropbox package. Docker and
Jupyter are alternatives when a local Julia installation is inconvenient or a
notebook interface is preferred. A separate Julia package is useful later,
when a model becomes a maintained project.

## Install Cropbox locally

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

Use `Pkg.status("Cropbox")` to check the installed version. The
[stable documentation](https://cropbox.github.io/Cropbox.jl/stable/) describes
the registered release; the
[development documentation](https://cropbox.github.io/Cropbox.jl/dev/) follows
`main` and may describe features not released yet. To try those features in a
separate project environment, use
`Pkg.add(url="https://github.com/cropbox/Cropbox.jl", rev="main")` instead.

## Use Docker

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

## Work in Jupyter

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

## Start modeling

Continue with the [Quick Start](@ref quick-start). These setup options are
alternatives; you do not need to install all of them.

When you are ready to save a reproducible environment, develop a model package,
or add a particular model, see [Projects and Model Packages](@ref model-projects).
