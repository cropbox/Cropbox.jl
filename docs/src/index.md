# Cropbox

Cropbox is a declarative modeling framework specifically designed for developing crop models. The goal is to let crop modelers focus on *what* the model should look like rather than *how* the model is technically implemented under the hood.

## Installation

[Cropbox.jl](https://github.com/cropbox/Cropbox.jl) is available through Julia package manager.

```julia
using Pkg
Pkg.add("Cropbox")
```

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
plot(r, :time, :a; kind = :line)
```

A more comprehensive guide in the next page will tell more about concepts and features behind Cropbox.
