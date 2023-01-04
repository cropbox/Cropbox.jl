```@setup Cropbox
using Cropbox
```

# Inspection

There are two inspective functions in Cropbox that allow us to look at systems more closely. For information regarding syntax, please check the [reference](@ref Inspection1).
* [`look()`](@ref look)
* [`dive()`](@ref dive)

## [`look()`](@id look)

The `look()` provides a convenient way of accessing variables within a system.

**Example**
```@example Cropbox
"""
This is a system.
"""
@system S begin
    """
    This is a parameter.
    """
    a ~ preserve(parameter)
end

look(S)
```
```@example Cropbox
look(S, :a)
```

!!! note "Note"
    There is a macro version of this function, `@look`, which allows you to access a variable without using a symbol.
    
    ```
    @look S
    @look S a
    @look S, a
    ```
    
    Both `@look S.a` and `@look S a` are identical to `look(S, :a)`.

## [`dive()`](@id dive)

The `dive()` function allows us to inspect an instance of a system by navigating through the hierarchy of variables displayed in a tree structure.

Pressing up/down arrow keys allows navigation. Press 'enter' to dive into a deeper level and press 'q' to come back. A leaf node of the tree shows an output of look regarding the variable. Pressing 'enter' again would return a variable itself and exit to REPL.

This function only works in a terminal environment and will not work in Jupyter Notebook.

**Example**
```
julia> @system S(Controller) begin
           a => 1 ~ preserve(parameter)
       end;
julia> s = instance(S);
julia> dive(s)
S
 → context = <Context>
   config = <Config>
   a = 1.0
```

