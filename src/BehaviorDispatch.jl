@generated function dispatch_behavior(beh::Type{Behavior{F, S}}, args...; kwargs...) where {F, S}
    DuckT = some_function_to_get_the_duck_type(beh, args)
    if isnothing(target_duck_type)
        error("No fitting iterate method found for $Duck")
    end
    ret_type = get_return_type(DuckT, beh)
    return :($(F.instance)(unwrap_where_this($S, $args)...;$kwargs...)::$ret_type)
end