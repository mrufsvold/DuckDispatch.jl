"""
HasDuckDispatch is a type used to mark a method which is dispatched on DuckTypes. 
Since we use Any as a placeholder to catch all fallbacks and then calculate the 
correct method to dispatch on. But we don't want to accidentally overwrite a method
with Any
"""
struct HasDuckDispatch end
struct IsDuckDispatch end

"""
    @with_interface(function_expression)
`@with_interface` allows for using an interface type as a type annotation to dispatch a new method
on any type which satisfies the interface requirements.

Some notes on the behavior:
    - Type-based dispatches take priority over interface dispatches. So `f(::AbstractArray)`
        will be the method dispatched for any array even if `f(::IsCollectable)` is defined.
    - This macro defines an additional method of the function which replaces all interfaces with
        `::Any` in the function signature. This allows it to capture the call and define the logic for
        wrapping and dispatching inputs with Guise types. However, this does mean that the
        following code will cause methods to be overwritten:
```julia
f(::Any) = "This is a generic fallback"
@with_interface f(::IsCollectable) = "This is my iterable interface dispatch"

f(1) # Errors because f(::Any) is now the dispatching function, and `1` is not iterable.
```
"""
macro with_interface(func_expr)
    if !is_function(func_expr)
        error("This isn't a function definition!")
    end
    
    # todo inner function needs to change its type annotations to Guise{<:DuckType, <:Any}
    inner_func = JLFunction(func_expr)
    func_args = FuncArg.(inner_func.args)
    
    outer_func_expr = build_outer_function(inner_func.name, func_args)
    inner_func_expr = build_inner_function!(inner_func, func_args)
    return quote
        $(esc(inner_func_expr))
        $(esc(outer_func_expr))
    end
end

function build_outer_function(name::Symbol, func_args::Vector{FuncArg})
    outer_func = JLFunction()
    outer_func.name = name

    # This creates function args that look like `arg1::(T<:DuckType ? Any : T)`
    # that allows us to subout any to capture the most generic dispatch and insert our own logic
    arg_names = get_name.(func_args)
    annotation_checks = arg_with_interface_type_check.(func_args)
    outer_func.args = [:($n::$T) for (n,T) in zip(arg_names, annotation_checks)]

    add_dispatch_body!(outer_func)

    outer_func_ast = codegen_ast(outer_func)
    mark_interface_dispatch_method = outer_func
    mark_interface_dispatch_method.body = quote nothing end
    pushfirst!(mark_interface_dispatch_method.args, :(::$HasDuckDispatch))

    return quote 
        # we add this has method check so that we don't accidentally overwrite an existing method
        if hasmethod($name, tuple($(annotation_checks...))) && !hasmethod($name, tuple($HasDuckDispatch, $(annotation_checks...)))
            error(lazy"Cannot create a new method for $name disptaching on an interface because there is already a method defined for $name($(tuple((annotation_checks...))))")
        end
        $(codegen_ast(mark_interface_dispatch_method))
        $outer_func_ast
    end
end

function build_inner_function!(inner_func, func_args)
    inner_func.args = arg_with_interface_wrap_check.(func_args)
    pushfirst!(inner_func.args, :(::$IsDuckDispatch))
    return codegen_ast(inner_func)
end




# Macro Helpers:

function add_dispatch_body!(outer_func::JLFunction)
    # the outer version of the function we create just calls an intermediate dispatch function
    # which holds all the logic for looking up interfaces, wrapping args, etc.
    # so the body we create here is just a call to `dispatch` passing the function and the args through
    arg_names = (arg.args[1] for arg in outer_func.args)
    body = xcall(dispatch, outer_func.name, :($(IsDuckDispatch)()), arg_names...)
    outer_func.body = codegen_ast(body)
end

##### Functions that are called in the result of the macro: #####

# args here are going to be types because we are still in the body of the generated function
function dispatch(f, args...)
    arg_types = typeof.(args)
    f_method_table = methods(f)
    f_sigs = Iterators.map(extract_arg_types, f_method_table.ms)
    f_sigs = collect(Iterators.filter(m -> types_can_be_wrapped(m, arg_types), f_sigs))
    length(f_sigs) != 1 && error(lazy"Expected 1 matching methods, got $(length(f_methods))")
    
    wrapped_args = map(add_interface_wrap, only(f_sigs), args)
    return f(wrapped_args...)
end


function types_can_be_wrapped(interface_method_args, arg_types)
    length(interface_method_args) != length(arg_types) && return false

    for (input_type, target_type) in zip(arg_types, interface_method_args)
        if target_type <: Guise
            !meets_requirements(target_type, input_type) && return false
        # if we aren't looking at an interface type, then we need to make sure that we have 
        # a arg that is a subtype directly
        elseif !(input_type <: target_type)
            return false
        end
    end
    return true
end

function add_interface_wrap(target_type, arg)
    if target_type <: Guise
        kind = extract_interface_kind(target_type)
        return wrap(kind, arg)
    end
    return arg
end

# @testitem "Dispatch AST Helpers" begin
#     using ExproniconLite: @test_expr, JLFunction
#     using SumTypes: @cases


#     jlf = JLFunction(:(f(a::Any, b::Int, c::Vector{T}) where T = "hi!"))
#     DuckDispatch.add_dispatch_body!(jlf)
#     @test_expr jlf.body == :($(DuckDispatch.dispatch)(f, $(DuckDispatch.IsDuckDispatch)(), a, b, c))
# end

# @testitem "Dispatch on Guise without macro" begin
#     import Base: iterate, length, eltype

#     struct IsIterable{T} <: DuckDispatch.DuckType end
#     DuckDispatch._required_methods(::Type{T}) where {T<:IsIterable} = (
#         DuckDispatch.RequiredMethod{eltype}(Tuple{DuckDispatch.This}),
#         DuckDispatch.RequiredMethod{iterate}(Tuple{DuckDispatch.This}),
#         DuckDispatch.RequiredMethod{iterate}(Tuple{DuckDispatch.This, Any})
#     )
    
#     function iterate(arg1::DuckDispatch.Guise{IsIterable{T}, <:Any}) where T
#         return iterate(DuckDispatch.unwrap(arg1))::Union{Nothing, Tuple{<:T, <:Any}}
#     end
#     function iterate(arg1::DuckDispatch.Guise{IsIterable{T}, <:Any}, arg2::Any) where T
#         return iterate(DuckDispatch.unwrap(arg1), arg2)::Union{Nothing, Tuple{<:T, <:Any}}
#     end
#     function eltype(x::DuckDispatch.Guise{IsIterable{T}, <:Any}) where T
#         return eltype(DuckDispatch.unwrap(x))::Type{T}
#     end

#     struct IsSizedIterator{T} <: DuckDispatch.DuckType end
#     DuckDispatch._required_methods(::Type{IsSizedIterator{T}}) where {T} = (
#         DuckDispatch.RequiredMethod{length}(Tuple{DuckDispatch.This}),

#     )
#     function length(x::DuckDispatch.Guise{IsSizedIterator{T}, <:Any}) where T
#         return length(DuckDispatch.unwrap(x))::Int
#     end

#     DuckDispatch.required_interfaces(::Type{IsSizedIterator{T}}) where {T} = (IsIterable{T},)
#     function iterate(arg1::DuckDispatch.Guise{IsSizedIterator{T}, <:Any}) where T
#         return iterate(DuckDispatch.rewrap(arg1, IsIterable{T}))::Union{Nothing, Tuple{<:T, <:Any}}
#     end
#     function iterate(arg1::DuckDispatch.Guise{IsSizedIterator{T}, <:Any}, arg2::Any) where T
#         return iterate(DuckDispatch.rewrap(arg1, IsIterable{T}), arg2)::Union{Nothing, Tuple{<:T, <:Any}}
#     end
#     function eltype(x::DuckDispatch.Guise{IsSizedIterator{T}, <:Any}) where T
#         return eltype(DuckDispatch.rewrap(x, IsIterable{T}))::Type{T}
#     end
    
#     # This is the stuff that needs to be created by the with_interface macro
#     function collect_ints(
#             ::DuckDispatch.IsDuckDispatch, # insert the DuckDispatch
#             x::DuckDispatch.Guise{IsSizedIterator{Int}, <:Any} # make sure DuckTypes are wrapped
#             )
#         return collect(x)
#     end

#     function collect_ints(x::Any)
#         return DuckDispatch.dispatch(
#             collect_ints, # pass dispatch the function name
#             DuckDispatch.IsDuckDispatch(), # insert an instance of DuckDispatch
#             x # pass all args
#             )
#     end

#     f_sigs = map(DuckDispatch.extract_arg_types, methods(collect_ints).ms)
#     @test length(f_sigs) == 2
#     @test DuckDispatch.types_can_be_wrapped(f_sigs[2], (DuckDispatch.IsDuckDispatch, Tuple{Int,Int}))
#     @test collect_ints((1,2))::Vector{Int} == [1,2]

#     DuckDispatch.@with_interface function collect_strings(x::IsSizedIterator{String})
#         return collect(x)
#     end

#     @test collect_strings(("a","b"))::Vector{String} == ["a","b"]
# end

