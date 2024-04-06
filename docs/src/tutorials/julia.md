```@setup Cropbox
using Cropbox
```

# [Getting Started with Julia](@id Julia)

Julia is a relatively new programming language designed for scientific computing in mind. It is a dynamic programming language as convenient as Python and R, but also provides high performance and extensibility as C/C++ and Fortran. Check the chart [here](https://www.tiobe.com/tiobe-index/) to see where Julia stands as a programming language among other languages today; its position has been rising fast.

If you already have a fair understanding of Julia or would like to skip ahead to learning about Cropbox, please go to [Getting Started With Cropbox](@ref cropbox).

## Installing Julia

You can download and install Julia from the [official Julia downloads page](https://julialang.org/downloads/). For new users, it is recommended to install the "Current stable release" for Julia. In general, you will want to install the 64-bit version. If you run into an issue installing the 64-bit version, you can try the 32-bit version. During installation, select "Add Julia to PATH". You can also add Julia to PATH after installation using the command-line interface (CLI).

For more detailed platform-specific instructions, you can check the [official Julia instructions](https://julialang.org/downloads/platform/).

If you are new to coding and require a development environment, check the [Installation section](@ref Installation) for more information.

## The Julia REPL

The quickest way to start using Julia is by opening the Julia executable or by running the command [julia] in your terminal or command prompt. In order to run [julia] from your terminal or command prompt, make sure that Julia is added to your PATH. 

By doing so, you can start an interactive session of Julia, also known as the REPL, which stands for "Read-Eval-Print Loop".

Using the REPL, you can start running simple commands like the following:

```@repl
a = 1
b = 2
c = a + b
```

## Variables

Variables in Julia refer to names that are associated with a value. The names can be associated with various different [types](https://docs.julialang.org/en/v1/manual/types/) of values. Take a look at the following example:

```@repl Cropbox
a = 1

b = "string"

c = [a, b]

d = @system D
```

!!! warning "Warning"
    Julia variables are not to be confused with Cropbox [variables](@ref variable) defined within Cropbox [systems](@ref system).