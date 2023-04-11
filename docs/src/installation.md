# [Installation](@id Installation)

## Installing Julia

Cropbox is a domain-specific language (DSL) for [Julia](https://julialang.org). To use Cropbox, you must first [download and install](https://julialang.org/downloads/) Julia. For new users, it is recommended to install the "Current stable release" for Julia. In general, you will want to install the 64-bit version. If you run into an issue installing the 64-bit version, you can try the 32-bit version. During installation, select "Add Julia to PATH". You can also add Julia to PATH after installation using the terminal.

```shell
export PATH="$PATH:/path/to/<Julia directory>/bin"
``` 

For more detailed platform-specific instructions, you can check the [official Julia instructions](https://julialang.org/downloads/platform/).

Once Julia is added to PATH, the interactive REPL can be started by double-clicking the Julia executable or running `julia` from the command line. 

## Using JupyterLab
While you can technically use the terminal or command prompt to run your code, it may be convenient to use an integrated development environment (IDE) or an interactive platform like [JupyterLab](https://jupyter.org/install). To add the Julia kernel to Jupyter, launch the REPL and add the IJulia package. 

```julia
using Pkg
Pkg.add("IJulia")
```
When you launch Jupyter, you should now be able to select a Julia kernel to run your notebook. 

## Installing Cropbox

[Cropbox.jl](https://github.com/cropbox/Cropbox.jl) is available through Julia package manager and can be installed using the Julia REPL.

```julia
using Pkg
Pkg.add("Cropbox")
```

## Using Docker

If you would like to skip the process of installing Julia and Cropbox on your machine, there is a [Docker image](https://hub.docker.com/repository/docker/cropbox/cropbox) with Cropbox precompiled for convenience. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) on your machine by following the instructions on the website and run the following command in the terminal or command prompt. 

```shell
$ docker run -it --rm -p 8888:8888 cropbox/cropbox
```
By default, this will launch a JupyterLab session that you can access by opening the printed URL in your browser. 

If REPL is preferred, you can directly launch an instance of Julia session.

```shell
docker run -it --rm cropbox/cropbox julia
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

## Using Binder

The docker image can be also launched via Binder without installing anything locally. This method is the least recommended due to its timeout duration.

[![Binder](https://mybinder.org/badge_logo.svg)](https://mybinder.org/v2/gh/cropbox/cropbox-binder/main)
