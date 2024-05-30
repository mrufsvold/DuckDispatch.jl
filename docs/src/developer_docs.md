# Developer Documentation
# Introduction
There are two fundamental pieces of this package: 
1) Constructing `DuckType`s and their `Behavior`s
2) Defining methods which can be dispatched on `DuckType`s
# Constructing `DuckType`s
## `Behavior`s
A `Behavior` represents a method that must be implemented for a `DuckType`. It has the form:
```julia
Behavior{F, T<:Tuple}
```
where `F` is the type of the function for this method and `T` is the type parameters for the arguments of the method. However, instead of having a specific `DuckType` as a type parameter, it is replace with `DuckDispatch.This`. `This` is a placeholder that lets any composed `DuckType` quickly insert itself when checking for matching methods.
## `DuckType`s
A `DuckType` has the following anatomy:
```julia
DuckType{
	Union{Behavior1, Behavior2, ...},
	Union{ComposedDuckType1, ComposedDuckType2, ...}
}
```
The first type parameter is a union of `Behavior` (see below) types that were added to the `DuckType` by the current definition. 

A user's specific `DuckType` is a struct which subtypes the `DuckType` that is composed of all the `Behavior`s they specify.

We can check if a specific type, `T`, implements all the `Behavior`s required by a `DuckType` by calling `quacks_like(SomeDuckType, T)`

## `Guise`
A `Guise` is a wrapper which allows a type to "pass" as a `DuckType` for method dispatching. It looks like this
```julia
Guise{<:DuckType, T}
```
Users should not normally be constructing a `Guise` directly. This is handled by the dispatching machinery provided by `DuckDispatch.jl`.

## `@duck_type`
This macro constructs the type definition for a new duck type and a method for each behavior that dispatches on a `Guise{ThisDuckType, <:Any}`. This specific method simply unwraps the arguments and passes on to the real method. 

It also implements a fallback `Guise{<:Any, <:Any}` version of the method which recursively descends through all the composed `DuckType`s and checks if there is an implied `DuckType` which has a `Behavior` for this method.

# `@duck_dispatch`
When we want to dispatch a method using a `DuckType`, we use `@duck_dispatch` to build the necessary infrastructure. Currently, this macro does a few things:

1) Checks to make sure it won't overwrite a regular generic method
2) Defines the user's method, replacing `DuckType`s with `Guise{DuckType}`s
3) Constructs a global constant with the current list of `DuckType` dispatched method signatures. This allows us to avoid calls to `methods` at runtime.
4) Constructs a generic method with the correct number of arguments to catch calls and do the `Guise` wrap operations.
