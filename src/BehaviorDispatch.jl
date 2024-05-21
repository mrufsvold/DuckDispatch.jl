@generated function dispatch_behavior(beh::Type{Behavior{F, S}}, args...; kwargs...) where {F, S}
    DuckT = some_function_to_get_the_duck_type(beh, args)
    og_duck = find_original_duck_type(DuckT, beh)
    if isnothing(target_duck_type)
        error("No fitting iterate method found for $Duck")
    end
    return :($(F.instance)($rewrap_where_this($S, $og_duck, $args)...;$kwargs...)::$get_return_type($DuckT, $beh))
end