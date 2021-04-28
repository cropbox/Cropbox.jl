# Cropbox

Cropbox is a declarative modeling framework specifically designed for developing crop models. The goal is to let crop modelers focus on *what* the model should look like rather than *how* the model is technically implemented under the hood.

## Installation

[Cropbox.jl](https://github.com/cropbox/Cropbox.jl) is available through Julia package manager.

```julia
using Pkg
Pkg.add("Cropbox")
```

There is a [Docker image](https://hub.docker.com/repository/docker/cropbox/cropbox) with Cropbox precompiled for convenience. By default, Jupyter Lab will be launched.

```shell
$ docker run -it --rm -p 8888:8888 cropbox/cropbox
```

If REPL is preferred, you can directly launch an instance of Julia session.

```shell
$ docker run -it --rm cropbox/cropbox julia
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.6.1 (2021-04-23)
 _/ |\__'_|_|_|\__'_|  |  Official https://julialang.org/ release
|__/                   |

julia>
```

The docker image can be also launched via Binder without installing anything local.

[![Binder](https://mybinder.org/badge_logo.svg)](https://mybinder.org/v2/gh/cropbox/cropbox-binder/main)

## Getting Started

Let's start with Cropbox.

```@example simple
using Cropbox
```

In Cropbox, **system** is where the model specification is written down in a slightly repurposed Julia syntax, which is an approach generally called domain specific language (DSL).

```@example simple
@system S(Controller) begin
    a(a) ~ accumulate(init = 1)
end
; # hide
```

In this simple example, our system `S` has a single variable named `a` which accumulates itself starting from an initial value of 1. Once the model is defined as a system, users can run simulations.

```@example simple
simulate(S) # hide
r = simulate(S, stop = 5)
show(stdout, "text/plain", r) # hide
```
Here is a line plot of the variable `a` after running simulation updated for five times.

```@example simple
visualize(r, :time, :a; kind = :line)
```

A more comprehensive guide in the next page will tell more about concepts and features behind Cropbox.
