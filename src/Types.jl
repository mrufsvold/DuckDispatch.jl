"""
`This` is a placeholder type which stands in for the current `DuckType` in a `Behavior` signature.
"""
struct This end

"""
`Behavior{F, Sig<:Tuple}` is a type that represents a method signature that a `DuckType` must implement.
- `F` is the function type that the `DuckType` must implement.
- `Sig` is the signature of the function that the `DuckType` must implement. Sig is a tuple of types, 
    where `This` is a placeholder for the `DuckType` itself.
"""
struct Behavior{F, Sig <: Tuple} end
"""
    `get_signature(::Type{Behavior}) -> NTuple{N, Type}` 
Returns the signature of a `Behavior` type.
"""
get_signature(::Type{Behavior{F, S}}) where {F, S} = S
"""
    `get_func_type(::Type{Behavior}) -> Type{F}`
Returns the function type of a `Behavior` type.
"""
get_func_type(::Type{Behavior{F, S}}) where {F, S} = F

"""
`DuckType{Behaviors, DuckTypes}` is a type that represents a DuckType.
- `Behaviors` is a Union of `Behavior` types that the `DuckType` implements.
- `DuckTypes` is a Union of `DuckType` types that the `DuckType` is composed of.
"""
abstract type DuckType{Behaviors, DuckTypes} end

"""
    `narrow(::Type{<:DuckType}, ::Type{T}) -> Type{<:DuckType}`
Returns the most specific `DuckType` that can wrap an objecet of type `T`.
This can be overloaded for a specific `DuckType` to provide more specific behavior.
"""
narrow(::Type{T}, ::Any) where {T <: DuckType} = T

"""
`Guise{DuckT, Data}` is a type that wraps an object of type `Data` and implements the `DuckType` `DuckT`.
"""
struct Guise{DuckT, Data}
    duck_type::Type{DuckT}
    data::Data
end
"""
    `get_duck_type(::Type{Guise{D, <:Any}}) -> Type{D}`
Returns the `DuckType` that a `Guise` implements.
"""
get_duck_type(::Type{Guise{D, T}}) where {D, T} = D
get_duck_type(::Type{Guise{D}}) where {D} = D
function get_duck_type(u::UnionAll)
    duck_type_internal_name = u.body.body.parameters[1].name
    duck_type_module = duck_type_internal_name.module
    duck_type_name = duck_type_internal_name.name
    duck_type = getfield(duck_type_module, duck_type_name)::Type{<:DuckType}
    return duck_type
end
get_duck_type(::G) where {G <: Guise} = get_duck_type(G)

"""
`TypeChecker{Data}` is a callable struct which checks if there is a method implemented for
`Data` that matches the signature of a `Behavior`.
"""
struct TypeChecker{Data}
    t::Type{Data}
end
function (::TypeChecker{Data})(::Type{B}) where {Data, B <: Behavior}
    sig_types = fieldtypes(get_signature(B))::Tuple
    func_type = get_func_type(B)
    replaced = map((x) -> x === This ? Data : x, sig_types)
    return !isempty(methods(func_type.instance, replaced))
end

"""
CheckQuacksLike{T} is a callable struct which wraps a Tuple{Types...} for some 
concrete args. When called on a ducktype method signature, it checks if all the args quack like
the method args.
"""
struct CheckQuacksLike{T}
    t::Type{T}
end
function (x::CheckQuacksLike{T})(::Type{M}) where {T, M}
    method_arg_types = fieldtypes(M)
    input_arg_types = (DispatchedOnDuckType, fieldtypes(T)...)
    can_quack = map(quacks_like, method_arg_types, input_arg_types)
    return all(can_quack)
end

"""
`DispatchedOnDuckType` is a singleton type that is used to indicate a method created
for duck type dispatching.
"""
struct DispatchedOnDuckType end
