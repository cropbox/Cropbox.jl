# [Installation](@id Installation)

## Install Julia

Cropbox is a domain-specific language (DSL) for [Julia](https://julialang.org). To use Cropbox, you must first [download and install](https://julialang.org/downloads/) Julia. For new users, it is recommended to install the "Current stable release" for Julia.

## Install Cropbox

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