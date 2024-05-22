`run` currently unwraps all the arguments passed in. However, it should really only unwrap arguments which
are related to the interface on which we are dispatching. 

The Meet type should be recursive with

Meet{I, M} where I <: DuckType M <: Union{Meet, Nothing}

then the dispatch function needs to recurse down the Meet nest until it finds an interface kind that matches the current function
```
function f(arg1::Guise{Meet{T, <:Any}, <:Any}, arg2) where T 
    if T <: MyGuise 
        return run(f, arg1, arg2)
    end
    f(peel_layer(arg1), arg)
    # this still suffers from the problem of peeling all interfaces 
end
```