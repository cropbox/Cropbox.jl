```@setup Cropbox
using Cropbox
```

# Visualization

There are three main functions in Cropbox used for visualization. For information regarding syntax, please check the [reference](@ref Visualization1).
* [`plot()`](@ref plot)
* [`visualize()`](@ref visualize)
* [`manipulate()`](@ref manipulate)

## [`plot()`](@id plot)

The `plot()` function is used to plot two-dimensional graphs.

**Two Vectors**

Let's start by making a simple plot by using two vectors of discrete values.

```@example Cropbox
x = [1, 2, 3, 4, 5]
y = [2, 4, 6, 8, 10]

plot(x, y)
```

**Multiple Vectors**

You can also plot multiple series, by using a vector of vectors.

```@example Cropbox
plot(x, [x, y])
```

**DataFrame**

We can also make a plot using a DataFrame and its columns. Recall that the `simulate()` function provides a DataFrame.

```@example Cropbox
@system S(Controller) begin
    x ~ advance
    y1(x) => 2x ~ track
    y2(x) => x^2 ~ track
end

df = simulate(S; stop=10)

p = plot(df, :x, [:y1, :y2])
```

### `plot!()`

`plot!()` is an extension of the `plot()` function used to update an existing `Plot` object `p` by appending a new graph made with `plot()`

**Example**
```@example Cropbox
@system S(Controller) begin
    x ~ advance
    y3(x) => 3x ~ track
end

df = simulate(S; stop=10)

plot!(p, df, :x, :y3)
```

## [`visualize()`](@id visualize)

The `visualize()` function is used to make a plot from an output collected by running simulations. It is essentially identical to running the `plot()` function with a DataFrame from the `simulate()` function, and can be seen as a convenient function to run both `plot()` and `simulate()` together.

**Example**
```@example Cropbox
@system S(Controller) begin
    x ~ advance
    y1(x) => 2x ~ track
    y2(x) => x^2 ~ track
end

v = visualize(S, :x, [:y1, :y2]; stop=10, kind=:line)
```

### `visualize!()`

`visualize!()` updates an existing `Plot` object `p` by appending a new graph generated with `visualize()`. 

**Example**
```@example Cropbox
@system S(Controller) begin
    x ~ advance
    y3(x) => 3x ~ track
end

visualize!(v, S, :x, :y3; stop=10, kind=:line)
```

## [`manipulate()`](@id manipulate)

The `manipulate` function has two different [methods](https://docs.julialang.org/en/v1/manual/methods/) for creating an interactive plot.

```
manipulate(f::Function; parameters, config=())
```
Create an interactive plot updated by callback f. Only works in Jupyter Notebook.

```
manipulate(args...; parameters, kwargs...)
```
Create an interactive plot by calling manipulate with visualize as a callback.
