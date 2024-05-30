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
    # I hate this too. But it works.
    duck_type_internal_name = u.body.body.parameters[1].name
    duck_type_module = duck_type_internal_name.module
    duck_type_name = duck_type_internal_name.name
    duck_type = getfield(duck_type_module, duck_type_name)::Type{<:DuckType}
    return duck_type
end
get_duck_type(::G) where {G <: Guise} = get_duck_type(G)

function replace_this(::Type{T}, ::Type{Data}) where {T, Data}
    field_types = static_fieldtypes(T)
    replaced = tuple_map((x) -> x === This ? Data : x, field_types)
    return Tuple{replaced...}
end
"""
`TypeChecker{Data}` is a callable struct which checks if there is a method implemented for
`Data` that matches the signature of a `Behavior`.
"""
struct TypeChecker{Data}
    t::Type{Data}
end
@generated function (::TypeChecker{Data})(::Type{B}) where {
        Data, B <: Behavior}
    replaced = replace_this(get_signature(B), Data)
    func_type = get_func_type(B)
    checks = :($static_hasmethod($(func_type.instance), $replaced) ||
               !isempty(static_methods($(func_type.instance), $replaced)))
    return checks
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
    method_arg_types = static_fieldtypes(M)
    input_arg_types = (DispatchedOnDuckType, static_fieldtypes(T)...)

    return tuple_all(quacks_like, method_arg_types, input_arg_types)
end

"""
`DispatchedOnDuckType` is a singleton type that is used to indicate a method created
for duck type dispatching.
"""
struct DispatchedOnDuckType end

# This makes VSCode missing ref happy
@static if false
    local TypeAnnotation, none, symbol, expr
end

@sum_type TypeAnnotation :hidden begin
    none
    symbol(::Symbol)
    expr(::Expr)
end

function type_annotation(t)
    if t isa Symbol
        return TypeAnnotation'.symbol(t)
    end
    return TypeAnnotation'.expr(t)
end

struct FuncArg
    name::Symbol
    type_annotation::TypeAnnotation
end
function FuncArg(arg)
    name, type_ann = if arg isa Symbol
        (arg, TypeAnnotation'.none)
    elseif arg.head == :(::) && length(arg.args) == 1
        (gensym(:arg), type_annotation(first(arg.args)))
    elseif arg.head == :(::) && length(arg.args) == 2
        (arg.args[1], type_annotation(arg.args[2]))
    else
        error(lazy"Unknown arg type $arg")
    end
    return FuncArg(name, type_ann)
end

function get_type_annotation(f::FuncArg)
    return @cases f.type_annotation begin
        none => :Any
        symbol(x) => x
        expr(x) => x
    end
end

get_name(f::FuncArg) = f.name
