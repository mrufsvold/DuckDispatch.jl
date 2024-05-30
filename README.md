# DuckDispatch

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mrufsvold.github.io/DuckDispatch.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mrufsvold.github.io/DuckDispatch.jl/dev/)
[![Build Status](https://github.com/mrufsvold/DuckDispatch.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/mrufsvold/DuckDispatch.jl/actions/workflows/CI.yml?query=branch%3Amaster)
[![Coverage](https://codecov.io/gh/mrufsvold/DuckDispatch.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/mrufsvold/DuckDispatch.jl)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

`DuckDispatch.jl` is an experimental package which attempts to make it easy to dispatch a method based on the behavior of a type, not its place in the type hierarchy. At a high-level, it allows the user to define a number of method signatures which constitute a `DuckType`. Then, any type which has an implementation for those methods can be wrapped in a `Guise{D<:DuckType, T}`. This `Guise` type is then hooked into the normal Julia dispatch machinery.

# Why?
It often does not care if an input is a vector, a channel, or a set; it matters that it is iterable. While a completely generic argument will work, it also provides no guarantees for correctness.

By dispatching on a `DuckType`, we get:
1) compile time guarantees that there won't be any method errors for the `Behavior`s defined for the `DuckType`
2) helpful errors for calls to a method that is not defined for the `DuckType`
3) a method signature that is more informative about the meaning of is arguments

# The Basics
To define an `Iterable` `DuckType`, we can do the following:

```julia
using DuckDispatch
@duck_type struct Iterable{T}
    function Base.iterate(::This)::Union{Nothing, Tuple{T, <:Any}} end
    function Base.iterate(::This, ::Any)::Union{Nothing, Tuple{T, <:Any}} end
    @narrow T -> Iterable{eltype(T)}
end
```

Now, we can create a new function that dispatches on this `DuckType`:
```julia
@duck_dispatch function my_collect(arg1::Iterable{T}) where {T}
    v = T[]
    for x in arg1
        push!(v, x)
    end
    return v
end

using Test
@test my_collect((1,2)) == [1,2]
@test my_collect(1:2) == [1,2]
@test my_collect((i for i in 1:2)) == [1,2]
```

`Iterable` is pretty limited without `length`. We can compose it with some new behaviors to build a more feature-rich `DuckType`!

```julia
@duck_type struct FiniteIterable{T} <: Union{Iterable{T}}
    function Base.length(::This)::Int end
    @narrow T -> FiniteIterable{eltype(T)}
end
@duck_dispatch function my_collect(arg1::FiniteIterable{T}) where {T}
    return T[x for x in arg1]
end
```

# More Information
See [the developer documentation](./docs/src/developer_docs.md) for more information the internals of this package.
