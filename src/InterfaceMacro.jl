struct RequireStatements
    interface_type::Symbol
    typevars::Any
    method_list::Vector{RequiredFunctionality}
    require::Union{Nothing, Expr}
    narrow::Union{Nothing, Expr}
end
function RequireStatements(jl_struct::JLStruct)
    method_list = RequiredFunctionality[]
    require = nothing
    narrow = nothing

    full_interface_name = get_full_struct_name(jl_struct)
    escaped_type_vars = jl_struct.typevars isa Nothing ? nothing : Expr[esc(t) for t in jl_struct.typevars]

    for expr in jl_struct.misc
        if expr.head == :macrocall
            if expr.args[1] == Symbol("@require")
                require = expr
            elseif expr.args[1] == Symbol("@narrow")
                narrow = expr
            end
        elseif is_function(expr)
            push!(
                method_list, 
                RequiredFunctionality(JLFunction(expr), full_interface_name, escaped_type_vars)
            )
        else
            error("Unknown expression in definition of $(jl_struct.name): $expr")
        end
    end
    return RequireStatements(jl_struct.name, jl_struct.typevars, method_list, require, narrow)
end

function find_require_statement(statements)
    check = (ex) -> ex.head == :macrocall && ex.args[1] == Symbol("@require")
    return findfirst(check, statements)
end

function find_narrow_statement(statements)
    check = (ex) -> ex.head == :macrocall && ex.args[1] == Symbol("@narrow")
    return findfirst(check, statements)
end

macro interface(interface_expr)
    return _interface(interface_expr)
end

function _interface(interface_expr)
    jl_struct = JLStruct(interface_expr)
    required_statements = RequireStatements(jl_struct)

    main_struct_expr = create_main_struct_def(interface_expr)
    required_method_expr = create_required_methods_func(required_statements)
    required_method_dispatch_exprs = create_exprs_for_required_methods(required_statements)

    # todo -- we need to remove the @require and the @narrow macro statements from .misc
    # we need to _required_methods to maybe return the MeetType of the required interfaces
    # then we need _required_methods to recursively descend into the meet types 

    # then we need to add a loop to the macro output that evals the rewrap function
    # for each inherited method 

    # lastly, we need to generate the narrow function for the new interface.

    # todo -- also need to dispatch for get_return_type
    return quote
        $main_struct_expr
        $required_method_expr
        $(required_method_dispatch_exprs...)
        
    end
end

"""
just creates `struct NewInterfaceName <: InterfaceKind end`
"""
function create_main_struct_def(interface_expr)
    # todo: how to make this struct documentable?
    jl_struct = JLStruct(interface_expr)
    empty!(jl_struct.constructors)
    empty!(jl_struct.misc)
    jl_struct.supertype = InterfaceKind
    return codegen_ast(jl_struct)
end

"""
creates this expr:

```
function _requires_methods(::Type{T}) where T<:NewInterfaceName
    return tuple(
        RequiredMethod{method1}(Tuple{This}), 
        RequiredMethod{method2}(Tuple{This, Other, Types, This})
        )
end
```
"""
function create_required_methods_func(required_statements::RequireStatements)
    method_list = required_statements.method_list
    req_method_exprs = map(create_required_method, method_list)
    req_method_ref = esc(GlobalRef(InterfaceDispatch, :_required_methods))
    return codegen_ast(JLFunction(;
        name = req_method_ref,
        args = [esc(:(::$Type{T}))],
        whereparams = [esc(:(T<:$(required_statements.interface_type)))],
        body = :(tuple($(req_method_exprs...)))
        ))
end


function create_required_method(req_method::JLFunction)
    t_anns = [
        is_This(t_ann) ? This : t_ann
        for t_ann in get_type_annotation.(FuncArg.(req_method.args))
    ]
    
    req_method = esc(:($RequiredMethod{$(req_method.name)}(Tuple{$(t_anns...)})))
    return req_method
end
function create_required_method(req_func::RequiredFunctionality)
    return create_required_method(req_func.func)
end

function create_exprs_for_required_methods(required_statements::RequireStatements)
    required_functionalities = required_statements.method_list

    req_exprs = Vector{Expr}(undef, length(required_functionalities))
    for (i, req_func) in enumerate(required_functionalities)
        req_exprs[i] = create_new_dispatch(req_func)
    end
    return req_exprs
end

function create_new_dispatch(rf::RequiredFunctionality)
    args = arg_with_this_check.(rf.args::Vector{FuncArg}, Ref(rf.interface_name))
    arg_names = get_arg_names(rf)
    jlf = JLFunction(;
        name = rf.name,
        args = args,
        body = quote
            return run($(rf.name), tuple($(arg_names...)))
        end,
        whereparams = rf.interface_type_vars
        )
    return codegen_ast(jlf)
end


@testitem "interface macro" begin
    import Base: eltype

    InterfaceDispatch.@interface struct HasEltype1{T}
        function eltype(::InterfaceDispatch.This)::T where T end
    end
    function InterfaceDispatch.narrow(::Type{HasEltype1}, ::Type{D}) where D
        E = eltype(D)
        return HasEltype1{E}
    end

    # macro needs to:
    # 1. create a struct that is a subtype of InterfaceKind
    @test HasEltype1 <: InterfaceDispatch.InterfaceKind
    # 2. create a function that returns the required methods
    @test InterfaceDispatch._required_methods(HasEltype1) == (
        InterfaceDispatch.RequiredMethod{eltype}(Tuple{InterfaceDispatch.This}),
    )
    # 3. create a new method for each required method
    @test length(methods(eltype, (HasEltype1,))) == 1

    # 4. for each required interface, add more new methods with unwrap
    function check_eltype(x)
        return eltype(x)
    end
    @test check_eltype(InterfaceDispatch.wrap(HasEltype1, [1])) == Int
end

