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

@generated function dispatch_behavior(beh::Type{Behavior{F, S}}, args...; kwargs...) where {F, S}
    DuckT = get_specific_duck_type(fieldtypes(S), args)
    og_duck = find_original_duck_type(DuckT, beh)
    if isnothing(og_duck)
        error("No fitting iterate method found for $DuckT")
    end
    return :($(F.instance)($rewrap_where_this($S, $og_duck, $args)...;$kwargs...)::$get_return_type($DuckT, $beh))
end