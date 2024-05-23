"""
    wrap_and_dispatch(f, args...; kwargs...)
Wrap the arguments in a Guise and dispatch the function `f` on the wrapped arguments.
"""
function wrap_and_dispatch(f, args...; kwargs...)
    dispatch_args = (DispatchedOnDuckType(), args...)
    relevant_method_sig = get_relevant_method_sig(f, dispatch_args)
    wrapped_args = map(wrap_with_guise, relevant_method_sig, dispatch_args)
    return f(wrapped_args...; kwargs...)
end

function get_relevant_method_sig(f, args)
    arg_types = typeof.(args)
    f_method_table = methods(f)
    f_sigs = Iterators.map(extract_arg_types, f_method_table.ms)
    f_sigs = collect(Iterators.filter(m -> types_can_be_wrapped(m, arg_types), f_sigs))
    length(f_sigs) != 1 &&
        error(lazy"Expected 1 matching methods, got $(length(f_sigs))")
    return only(f_sigs)
end

function types_can_be_wrapped(duck_typed_args, arg_types)
    length(duck_typed_args) == length(arg_types) || return false

    for (input_type, target_type) in zip(arg_types, duck_typed_args)
        if target_type <: Guise
            DuckT = get_duck_type(target_type)
            !quacks_like(DuckT, input_type) && return false
            # if we aren't looking at an interface type, then we need to make sure that we have 
            # a arg that is a subtype directly
        elseif !(input_type <: target_type)
            return false
        end
    end
    return true
end

function wrap_with_guise(target_type, arg)
    if target_type <: Guise
        DuckT = get_duck_type(target_type)
        return wrap(DuckT, arg)
    end
    return arg
end