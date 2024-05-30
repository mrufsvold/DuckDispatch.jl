function get_specific_duck_type(sig, arg_types)
    this_arg_types = Union{}
    for i in eachindex(sig)
        if sig[i] == This
            this_arg_types = Union{this_arg_types, get_duck_type(arg_types[i])}
        end
    end
    duck_types = tuple_collect(this_arg_types)
    length(duck_types) == 1 && return only(duck_types)
    error("No specific duck type found for $sig and $arg_types")
end

"""
    `dispatch_behavior(::Type{Behavior{F, S}}, args...; kwargs...) -> Any`
Dispatches a behavior to the correct method based on the arguments passed in.
It is called by the fallback definition of a behavior. It looks up the original
DuckType that implemented the behavior and calls the method on that DuckType.
"""
@inline function dispatch_behavior(
        behavior::Type{Behavior{F, S}}, args...; kwargs...) where {F, S}
    DuckT = get_specific_duck_type(static_fieldtypes(S), args)
    OGDuckT = find_original_duck_type(DuckT, behavior)
    if isnothing(OGDuckT)
        throw(MissingBehaviorCall(F, typeof(args), DuckT))
    end
    return @inline F.instance(rewrap_where_this(S, OGDuckT, args)...;
        kwargs...)
end

"""
    `run_behavior(f, args...; kwargs...) -> Any`
This function is called by the specific definition of a behavior created for a new
DuckType.
"""
function run_behavior(f, args...; kwargs...)
    unwrapped_args = unwrap.(args)
    return f(unwrapped_args...; kwargs...)
end
