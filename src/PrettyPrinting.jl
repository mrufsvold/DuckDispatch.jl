# function Base.show(io::IO, ::Type{Behavior{F, S}}) where {F, S}
#     print(io, "Behavior{", string(F.instance), ", ", tuple(static_fieldtypes(S)...), "}")
# end

function get_duck_type_name(::Type{D}) where {D<:DuckType}
    (name, params) = if D isa UnionAll
        (D.body.name.name, D.body.parameters)
    else
        (D.name.name, D.parameters)
    end
    if isempty(params)
        return string(name)
    end
    return string(name) * "{" * (map(string, params)...) * "}"
end

function Base.show(io::IO, ::Type{D}) where {D<:DuckType}
    duck_type_name = get_duck_type_name(D)
    print(io, duck_type_name)
    behaviors = DuckDispatch.all_behaviors_of(D)
    print(io, "\n  Behaviors:\n    ")
    
    number_to_show = min(3, length(behaviors)-1)
    for b in Iterators.take(behaviors, number_to_show)
        print(io, b)
        print(io, ",","\n    ")
    end
    print(io, behaviors[number_to_show+1])
    
    length(behaviors) > number_to_show+1 && print(io, ",\n    ... (Behaviors omitted. call `DuckDispatch.all_behaviors_of(duck_type)` to see all)")
end

function Base.show(io::IO, ::Type{Guise{D, T}}) where {D, T}
    print(io, "Guise{", get_duck_type_name(D), ", ", T, "}")
end

function Base.show(io::IO, g::G) where {G<:Guise}
    print(io, G, " wrapping:\n", g.data)
end
