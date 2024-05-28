macro duck_dispatch(ex)
    return duck_dispatch_logic(ex)
end

function duck_dispatch_logic(ex)
    f = JLFunction(ex)

    func_args = FuncArg.(f.args)

    arg_count = length(f.args)
    anys = tuple((Any for _ in f.args)...)
    untyped_args = tuple((get_name(func_arg) for func_arg in func_args)...)
    user_type_annotations = get_type_annotation.(func_args)

    user_args_with_guise_check = arg_with_guise_wrap_check.(func_args)
    pushfirst!(user_args_with_guise_check, :(::$DispatchedOnDuckType))
    f.args = user_args_with_guise_check
    f_name = esc(f.name)
    user_func = esc(codegen_ast(f))

    get_method_sym = gensym(:get_methods)
    get_method_sym_esc = esc(get_method_sym)

    current_methods_sym = gensym(:current_methods)
    current_methods_esc = esc(current_methods_sym)
    func_name_sym = gensym(:func_name)
    func_name_sym_esc = esc(func_name_sym)
    replace_get_method = Expr(:quote,
        quote
            function (::typeof($get_methods))(::Type{typeof(Expr(:$, $func_name_sym))})
                return tuple(
                    Tuple{$(user_type_annotations...)},
                    Expr(:$, :($current_methods_sym))...
                )
            end
        end
    )

    return quote
        # We can't get typeof() on a function that hasn't been defined yet
        # so first we make sure the name exists
        function $f_name end

        # this gets the list of ducktype methods currently defined (defaults to ())
        $current_methods_esc = $get_methods(typeof($f_name))

        # Here we will check to make sure there isn't already a normal function that would
        # be overwritten by the ducktype fallback method
        if $hasmethod($f_name, $anys) &&
           any(map($length_matches, $current_methods_esc, Iterators.repeated($arg_count)))
            error("can't overwrite " * string($f_name))
        end

        # Core.@__doc__
        $user_func

        function (f::typeof($f_name))($(untyped_args...); kwargs...)
            arg_types = get_arg_types(tuple($(untyped_args...)))
            wrapped_args = wrap_args(f, arg_types)
            return @inline f($DispatchedOnDuckType(), wrapped_args...; kwargs...)
        end

        # Update the get_methods function to include the new method
        # have to return to f.name because @eval doesn't like :escape
        $func_name_sym_esc = $f_name
        $get_method_sym_esc = $get_methods
        eval($replace_get_method)

        # clear out current_methods var so we don't consume extra memory
        current_methods_esc = nothing
    end
end

"""
    get_methods(::Type{F})
Returns the list of DuckType methods that are implemented for the function `F`.
"""
function get_methods(::Type{F}) where {F}
    return ()
end

function wrap_with_guise(target_type::Type{T}, arg) where {T}
    DuckT = if T <: DuckType
        target_type
    elseif T <: Guise
        get_duck_type(target_type)
    else
        return arg
    end
    return wrap(DuckT, arg)
end

Base.@constprop :aggressive function get_arg_types(::T) where {T}
    return fieldtypes(T)
end

Base.@constprop :aggressive function wrap_args(::F, args) where {F}
    ms = get_methods(F)
    arg_types = typeof(args)
    check_quacks_like = CheckQuacksLike(arg_types)

    # this is a tuple of bools which indicate if the method matches the input args
    quack_check_result = map(check_quacks_like, ms)

    number_of_matches = sum(quack_check_result)
    number_of_matches == 1 || error("Expected 1 matching method, got $number_of_matches")

    match_index = findfirst(quack_check_result)
    method_match = ms[match_index]
    method_types = fieldtypes(method_match)
    wrapped_args = map(wrap_with_guise, method_types, args)
    return wrapped_args
end

function check_param_for_duck_and_wrap(T)
    if T <: Type
        return T <: DuckType ? Guise{T, <:Any} : T
    end
    if T isa TypeVar
        return T
    end
    error("Unexpected type annotation $T")
end

function arg_with_guise_wrap_check(func_arg::FuncArg)
    return @cases func_arg.type_annotation begin
        none => :($(func_arg.name)::Any)
        [symbol, expr](type_param) => :($(func_arg.name)::($(check_param_for_duck_and_wrap($type_param))))
    end
end

function length_matches(arg_types, arg_count)
    return length(fieldtypes(arg_types)) == arg_count
end