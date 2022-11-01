!!! warning "Warning"
    This page is incomplete. Please check the Reference page for information regarding functions.

# Inspection

There are two inspective functions in Cropbox that allow us to look at systems more closely.

```@contents
Pages = ["inspection.md"]
```

## `look()`

`look()` provides a convenient way of accessing variables within a system.

```
look(s, :a)
```

!!! `note` "Note"
    There is a macro version of this function, `@look`, which allows you to access a variable without using a symbol. Both `@look s.a` and `@look s a` are identical to `look(s, :a)`.

## `dive()`

