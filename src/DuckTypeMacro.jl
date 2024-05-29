macro duck_type(duck_type_expr)
    return _duck_type(duck_type_expr)
end

function _duck_type(duck_type_expr)
    jl_struct = JLStruct(duck_type_expr)

    required_behaviors, narrow = get_required_behaviors(jl_struct)
    @show narrow
    behaviors = [behavior.behavior for behavior in required_behaviors]

    all_func_exprs = Iterators.flatmap(required_behaviors) do rb
        (esc(codegen_ast(rb.general_catch)), esc(codegen_ast(rb.specific_catch)))
    end

    # grab the pieces of the struct that we need
    type_def = JLStruct(;
        name = jl_struct.name,
        typevars = jl_struct.typevars,
        supertype = duck_super_type(jl_struct, behaviors),
        line = jl_struct.line,
        doc = jl_struct.doc
    )

    quote
        $(esc(codegen_ast(type_def)))
        $(codegen_ast(narrow))
        $(all_func_exprs...)
    end
end

struct RequiredBehavior
    behavior::Expr
    general_catch::JLFunction
    specific_catch::JLFunction
end

function get_required_behaviors(jl_struct::JLStruct)
    required_behaviors = RequiredBehavior[]
    narrow = nothing
    for expr in jl_struct.misc
        if is_function(expr)
            general_func, behavior, func_args = make_general_function(expr)
            specific_func = make_specific_function(expr, func_args, jl_struct)
            push!(
                required_behaviors, RequiredBehavior(behavior, general_func, specific_func))
        elseif expr.head == :macrocall && expr.args[1] == Symbol("@narrow")
            narrow = make_narrow(jl_struct.name, expr)
        end
    end
    return (required_behaviors, narrow)
end

function make_narrow(duck_name, expr)
    line_node, user_narrow_def = if expr.args[2] isa LineNumberNode
        (expr.args[2], JLFunction(expr.args[3]))
    else
        (nothing, JLFunction(expr.args[2]))
    end
    @assert length(user_narrow_def.args)==1 "narrow must take exactly one argument which is the type of the object to be wrapped."
    user_arg_name = get_name(FuncArg(only(user_narrow_def.args)))
    narrow_f = JLFunction(quote
        function $(GlobalRef(@__MODULE__, :narrow))(::Type{<:$(esc(duck_name))},
                ::Type{$(esc(user_arg_name))}) where {$(esc(user_arg_name))}
            $(esc(user_narrow_def.body))
        end
    end)
    narrow_f.line = line_node
    return narrow_f
end

function make_general_function(expr)
    general_func = JLFunction(expr)
    func_args = FuncArg.(general_func.args)
    general_func.rettype = nothing
    general_func.args = [if_This_then_expr(
                             func_arg, :($Guise{<:Any, <:Any}))
                         for func_arg in func_args]
    behavior = :($Behavior{
        typeof($(general_func.name)),
        Tuple{$(get_type_annotation.(func_args)...)}
    })
    general_func.body = quote
        $dispatch_behavior(
            $behavior,
            $(get_name.(func_args)...)
        )
    end
    return (general_func, behavior, func_args)
end

function make_specific_function(expr, func_args, jl_struct)
    specific_func = JLFunction(expr)
    add_whereparams!(specific_func, jl_struct.typevars)
    specific_func.args = [if_This_then_expr(
                              func_arg, :(
                                  $Guise{
                                  $(jl_struct.name){$(jl_struct.typevars...)}, <:Any}
                              )
                          )
                          for func_arg in func_args]
    specific_func.body = quote
        $run_behavior($(specific_func.name), $(get_name.(func_args)...))
    end
    return specific_func
end

function if_This_then_expr(func_arg::FuncArg, expr)
    t_ann = get_type_annotation(func_arg)
    n = get_name(func_arg)
    return :($n::($t_ann === $This ? $expr : $t_ann))
end

function add_whereparams!(jl_func::JLFunction, typevars)
    where_list = if jl_func.whereparams isa Nothing
        []
    else
        jl_func.whereparams
    end
    # we want to insert the typevars from the struct def first because they
    # come first in the language of the macro. But we also want to retain their order
    # in case the are dependent on each other. So we reverse, then pushfirst
    for t in Iterators.reverse(typevars)
        # we also need to check if the typevar is already in the list
        # duplicates will throw an error
        if !(t in where_list)
            pushfirst!(where_list, t)
        end
    end
    jl_func.whereparams = where_list
end

function duck_super_type(jl_struct, behaviors)
    super_type_union = jl_struct.supertype isa Nothing ?
                       Union{} :
                       :(Union{$(jl_struct.supertype)})

    super_block = quote
        $DuckType{
            Union{$(behaviors...)},
            $super_type_union
        }
    end
    return super_block
end
