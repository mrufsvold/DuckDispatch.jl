macro duck_dispatch(ex)
    return duck_dispatch_logic(ex)
end

function duck_dispatch_logic(ex)
    f = JLFunction(ex)

    func_args = FuncArg.(f.args)

    arg_count = length(f.args)
    anys = tuple((Any for _ in f.args)...)
    untyped_args = tuple((get_name(func_arg) for func_arg in func_args)...)
    type_params = [esc(gensym(Symbol("T$i"))) for i in 1:arg_count]
    paramed_args = [:(($a)::($p)) for (a, p) in zip(untyped_args, type_params)]
    user_args_with_guise_check = arg_with_guise_wrap_check.(func_args)
    pushfirst!(user_args_with_guise_check, :(::$DispatchedOnDuckType))

    f.args = user_args_with_guise_check
    f_name = esc(f.name)
    user_func = esc(codegen_ast(f))

    return quote
        # We can't get typeof() on a function that hasn't been defined yet
        # so first we make sure the name exists
        function $f_name end

        # Here we will check to make sure there isn't already a normal function that would
        # be overwritten by the ducktype fallback method
        if $hasmethod($f_name, $anys) &&
           !any(map($is_duck_dispatched, $methods($f_name), Iterators.repeated($arg_count)))
            error("can't overwrite " * string($f_name))
        end

        Core.@__doc__ $user_func

        const duck_sigs = let
            ms = $methods($f_name)
            sig_types = map(extract_sig_type, ms)
            filter!(is_dispatched_on_ducktype, sig_types)
            duck_sigs = unwrap_guise_types.(sig_types)
            Tuple{duck_sigs...}
        end

        function (f::typeof($f_name))(
                $(paramed_args...); kwargs...) where {$(type_params...)}
            args = tuple($(untyped_args...))::Tuple{$(type_params...)}
            wrapped_args = wrap_args(duck_sigs, args)
            return @inline f($DispatchedOnDuckType(), wrapped_args...; kwargs...)
        end
    end
end

"""
    get_methods(::Type{F})
Returns the list of DuckType methods that are implemented for the function `F`.
"""
function get_methods(::Type{F}) where {F}
    return ()
end

function wrap_with_guise(::Type{T}, arg::D) where {T, D}
    DuckT = if T <: DuckType
        T
    else
        return arg
    end
    return wrap(DuckT, arg)::Guise{narrow(DuckT, D), D}
end

function unwrap_guise_types(::Type{T}) where {T}
    types = map(fieldtypes(T)) do t
        t <: Guise ? get_duck_type(t) : t
    end
    return Tuple{types...}
end

function is_duck_dispatched(m::Method, arg_count)
    sig_types = fieldtypes(m.sig)
    # the signature will have Tuple{typeof(f), DispatchedOnDuckType, arg_types...}
    length(sig_types) != 2 + arg_count && return false
    sig_types[2] != DispatchedOnDuckType && return false
    return true
end

function extract_sig_type(m::Method)
    sig = m.sig
    sig_types = fieldtypes(sig)[2:end]
    return Tuple{sig_types...}
end

function is_dispatched_on_ducktype(sig)
    return fieldtypes(sig)[1] == DispatchedOnDuckType
end

function wrap_args(::Type{T}, args) where {T}
    duck_sigs = fieldtypes(T)
    check_quacks_like = CheckQuacksLike(typeof(args))

    # this is a tuple of bools which indicate if the method matches the input args
    quack_check_result = tuple_map(check_quacks_like, duck_sigs)

    number_of_matches = sum(quack_check_result)
    # todo make this a MethodError
    number_of_matches == 0 &&
        error("Could not find a matching method for the given arguments.")
    method_types = most_specific_method(T, Val(quack_check_result))
    wrapped_args = wrap_each_arg(method_types, args)
    return wrapped_args
end

@generated function wrap_each_arg(::Type{T}, args) where {T}
    types = fieldtypes(T)
    vars = [gensym(:var) for _ in types]
    input_types = fieldtypes(args)
    calcs = [:($v = $wrap_with_guise($t, args[$i]::$in_t))
             for (i, (v, t, in_t)) in enumerate(zip(vars, types, input_types))]
    res = :(return ($(vars...),))
    return quote
        $(calcs...)
        $res
    end
end

Base.@assume_effects :foldable function get_most_specific(quack_check_result, duck_sigs)
    matches = [duck_sigs[[quack_check_result...]]...]::Vector
    sort!(matches; lt = implies)
    return first(matches)
end

@generated function most_specific_method(
        ::Type{T}, ::Val{quack_check_result}) where {T, quack_check_result}
    duck_sigs = fieldtypes(T)
    method_match = get_most_specific(quack_check_result, duck_sigs)
    method_types = Tuple{fieldtypes(method_match)[2:end]...}
    return :($method_types)
end

function check_param_for_duck_and_wrap(T)
    if T isa Type
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
        [symbol, expr](type_param) => :($(func_arg.name)::(($check_param_for_duck_and_wrap($type_param))))
    end
end

function length_matches(arg_types, arg_count)
    return length(fieldtypes(arg_types)) == arg_count
end