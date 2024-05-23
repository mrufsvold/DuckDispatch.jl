# DuckDispatch

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mrufsvold.github.io/DuckDispatch.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mrufsvold.github.io/DuckDispatch.jl/dev/)
[![Build Status](https://github.com/mrufsvold/DuckDispatch.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/mrufsvold/DuckDispatch.jl/actions/workflows/CI.yml?query=branch%3Amaster)
[![Coverage](https://codecov.io/gh/mrufsvold/DuckDispatch.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/mrufsvold/DuckDispatch.jl)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

An experimental package with a goal to make it easy to dispatch a method based on the behavior of a type, not its place in the type heirarchy. At a high-level, it allows the user to define a number of method signatures which constitute a `DuckType`. Then, any type which has an implementation for those methods can be wrapped in a `Guise{D<:DuckType, T}`. This `Guise` type is then hooked into the normal Julia dispatch machinary.

A `Guise` wrap provides four benefits:
1. Any type that will work in a function will automatically dispatch to that function
2. Only the methods which are specifically defined for a `DuckType` will work. If a callee function tries to call another method, a helpful error about the `DuckType`'s defined methods is displayed.
3. A `DuckType` can define a contract for the return type of each method it requires. Again, this allows for helpful error messages if a wrapped data type returns an unexpected type.
4. Data explicitly wrapped in `Guise{SomeDuckType, Any}`, can avoid dynamic dispatch until the leaf method call. This can be helpful when iterating over heterogenous datatypes which all meet the requirements of a `DuckType`. 
