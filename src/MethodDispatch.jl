macro duck(ex)
    return duck_macro_logic(ex)
end

function duck_macro_logic(ex)
    current_methods = gensym(:current_methods)
    new_methods = gensym(:new_methods)

    f = JLFunction(ex)

    anys = [Any for _ in f.args]
    arg_count = length(anys)

    func_args = FuncArg.(inner_func.args)

    user_args_with_guise_check = arg_with_guise_wrap_check.(func_args)
    untyped_args = tuple((get_name(func_arg) for func_arg in func_args)...)
    user_type_annotations = get_type_annotation.(func_args)

    quote
        if !isdefined(@__MODULE__, $(f.name))
            function $(f.name) end
        end
        # this gets the list of ducktype methods currently defined (defaults to ())
        $current_methods = $get_methods(typeof($(f.name)))

        # Here we will check to make sure there isn't already a normal function that would
        # be overwrite by the ducktype fallback method
        if $hasmethod($(f.name), ($(anys...))) &&
           any(map(length_matches, $current_methods, Iterators.repeated($arg_count)))
            error("can't overwrite f")
        end

        @__doc__
        @inline function $(f.name)($(user_args_with_guise_check...))
            # user body
        end

        function (f::typeof($(f.name)))($(untyped_args...); kwargs...)
            wrapped_args = wrap_args(f, $untyped_args)
            return f(wrapped_args...; kwargs...)
        end

        $new_methods = tuple(Tuple{$(user_type_annotations...)}, $current_methods...)
        # Update the get_methods function to include the new method
        @eval function get_methods(::Type{typeof($(f.name))})
            return Expr(:$, $new_methods)
        end

        # clear out current_methods var so we don't consume extra memory
        $current_methods = nothing
        $new_methods = nothing
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

function wrap_args(::F, args) where {F}
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

function arg_with_guise_wrap_check(func_arg::FuncArg)
    return @cases func_arg.type_annotation begin
        none => :($(func_arg.name)::Any)
        [symbol, expr](type_param) => :($(func_arg.name)::($type_param <: $DuckType ?
                                                           $Guise{$type_param, <:Any} :
                                                           $type_param))
    end
end

function length_matches(arg_types, arg_count)
    return length(fieldtypes(arg_types)) == arg_count
end