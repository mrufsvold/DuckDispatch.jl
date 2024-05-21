module R
using JET
using ExproniconLite
using BangBang: append!!

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
struct Behavior{F, Sig<:Tuple} end
"""
    `get_signature(::Type{Behavior}) -> NTuple{N, Type}` 
Returns the signature of a `Behavior` type.
"""
get_signature(::Type{Behavior{F,S}}) where {F,S} = S
"""
    `get_func_type(::Type{Behavior}) -> Type{F}`
Returns the function type of a `Behavior` type.
"""
get_func_type(::Type{Behavior{F,S}}) where {F,S} = F


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
    `get_top_level_behaviors(::Type{<:DuckType}) -> Union{Behavior...}`
Returns the top level behaviors of a `DuckType` (specifically, the behaviors that 
the `DuckType` implements directly).
"""
function get_top_level_behaviors(::Type{D}) where D<:DuckType
    sup = supertype(D)
    sup === Any && return extract_behaviors(D)
    return get_top_level_behaviors(sup)
end
# helper function to extract the behaviors from the abstract DuckType
extract_behaviors(::Type{DuckType{B,D}})  where {B,D} = B
"""
    `get_duck_types(::Type{<:DuckType}) -> Union{DuckType...}`
Returns the duck types that a `DuckType` is composed of.
"""
function get_duck_types(::Type{D}) where D<:DuckType
    sup = supertype(D)
    sup === Any && return extract_duck_types(D)
    return get_duck_types(sup)
end
# helper function to extract the duck types from the abstract DuckType
extract_duck_types(::Type{DuckType{B,D}}) where {B,D} = D

"""
    `all_behaviors_of(::Type{D}) -> Tuple{Behavior...}`
Returns all the behaviors that a `DuckType` implements, including those of its composed `DuckTypes`.
"""
function all_behaviors_of(::Type{D}) where D <: DuckType
    return tuple_collect(behaviors_union(D))
end

"""
    `tuple_collect(::Type{Union{Types...}}) -> Tuple(Types...)`
Returns a tuple of the types in a Union type.
"""
@generated function tuple_collect(::Type{U}) where U
    U === Union{} && return ()
    types = tuple(Base.uniontypes(U)...)
    call = xcall(tuple, types...)
    return codegen_ast(call)
end
# helper function for behaviors_union
function _behaviors_union(::Type{D}) where D 
    this_behavior_union = get_top_level_behaviors(D)
    these_duck_types = tuple_collect(get_duck_types(D))
    length(these_duck_types) == 0 && return this_behavior_union
    return Union{this_behavior_union, _behaviors_union(these_duck_types...)}
end
"""
    `behaviors_union(::Type{D}) -> Union{Behavior...}`
Returns the union of all the behaviors that a `DuckType` implements, including those of its composed `DuckTypes`.
"""
@generated function behaviors_union(::Type{D}) where D 
    u = _behaviors_union(D)
    return :($u)
end

"""
    `find_original_duck_type(::Type{D}, ::Type{B}) -> Union{Nothing, DataType}`
Returns the DuckType that originally implemented a behavior `B` in the DuckType `D`.
This allows us to take a `DuckType` which was composed of many others, find the original,
and then rewrap to that original type.
"""
function find_original_duck_type(::Type{D}, ::Type{B}) where {D,B}
    these_behaviors = tuple_collect(get_top_level_behaviors(D))
    if any(implies(b, B) for b in these_behaviors)
        return D
    end
    for dt in tuple_collect(get_duck_types(D))
        child_res = find_original_duck_type(dt, B)::Union{Nothing, DataType}
        !isnothing(child_res) && return child_res
    end
end

"""
`Guise{DuckT, Data}` is a type that wraps an object of type `Data` and implements the `DuckType` `DuckT`.
"""
struct Guise{DuckT, Data}
    data::Data
end
"""
    `get_duck_type(::Type{Guise{D, <:Any}}) -> Type{D}`
Returns the `DuckType` that a `Guise` implements.
"""
get_duck_type(::Type{Guise{D, <:Any}}) where {D} = D

"""
    implies(::Type{DuckType}, ::Type{DuckType}})
Return true if the first DuckType is a composition that contains the second DuckType.
"""
function implies(::Type{D1}, ::Type{D2}) where {D1<:DuckType, D2<:DuckType}
    # If we get an exact match between two DuckTypes, we can short-circuit to true
    D1 === D2 && return true

    # We can also check all the behaviors of D2 and see if they are in the union of
    # behaviors for D1. First, we try to just use the type system to check if D2 <: D1
    behaviors_union(D2) <: behaviors_union(D1) && return true
    
    # If that fails, we need to check the behaviors of D2 one by one
    d1_behaviors = all_behaviors_of(D1)
    for b2 in all_behaviors_of(D2)
        any(implies(b1, b2) for b1 in d1_behaviors) || return false
    end
    return true
end
# most basic check is whether the signature of the the second behavior is a subtype of the first
function implies(::Type{Behavior{F1, S1}}, ::Type{Behavior{F2, S2}}) where {F1, S1, F2, S2} 
    return F1===F2 && S2 <: S1
end

"""
`TypeChecker{Data}` is a callable struct which checks if there is a method implemented for
`Data` that matches the signature of a `Behavior`.
"""
struct TypeChecker{Data}
    t::Type{Data}
end
function (::TypeChecker{Data})(::Type{B}) where {Data, B<:Behavior}
    sig_types = fieldtypes(get_signature(B))::Tuple
    func_type = get_func_type(B)
    replaced = map((x) -> x === This ? Data : x, sig_types)
    return hasmethod(func_type.instance, replaced)
end

"""
    `quacks_like(Duck, Data) -> Bool`
Checks if `Data` implements all required `Behavior`s of `Duck`.
"""
@generated function quacks_like(::Type{Duck}, ::Type{Data}) where {Duck<:DuckType, Data}
    type_checker = TypeChecker{Data}(Data)
    behavior_list = all_behaviors_of(Duck)
    check_quotes = Expr[
        :($type_checker($b) || return false)
        for b in behavior_list
    ]
    return Expr(:block, check_quotes..., :(return true))
end

"""
    `wrap(::Type{Duck}, data::T) -> Guise{Duck, T}`
Wraps an object of type `T` in a `Guise` that implements the `DuckType` `Duck`.
"""
function wrap(::Type{Duck}, data::T) where {Duck<:DuckType, T}
    NarrowDuckType = narrow(Duck, T)::Type{<:Duck}
    quacks_like(NarrowDuckType, T) && return Guise{NarrowDuckType,T}(data)
    error("Type $T does not implement the methods required by $NarrowDuckType")
end

"""
    `unwrap(g::Guise) -> Any`
Returns the data wrapped in a `Guise`.
"""
unwrap(x::Guise) = x.data
"""
    `rewrap(g::Guise{Duck1, <:Any}, ::Type{Duck2}) -> Guise{Duck2, <:Any}`
Rewraps a `Guise` to implement a different `DuckType`.
"""
rewrap(x::Guise{I1, <:Any}, ::Type{I2}) where {I1, I2<:DuckType} = wrap(I2, unwrap(x))

"""
    `unwrap_where_this(sig::Type{<:Tuple}, args::Tuple) -> Tuple`
For each element of `args`, if the corresponding element of `sig` is `This`, unwrap that element.
"""
function unwrap_where_this(sig::Type{<:Tuple}, args::Tuple)
    return map(sig, args) do (T, arg)
        T === This ? unwrap(arg) : arg
    end
end

@generated function dispatch_required_method(beh::Type{Behavior{F, S}}, args...; kwargs...) where {F, S}
    DuckT = some_function_to_get_the_duck_type(beh, args)
    if isnothing(target_duck_type)
        error("No fitting iterate method found for $Duck")
    end
    ret_type = get_return_type(DuckT, beh)
    return :($(F.instance)(unwrap_where_this($S, $args)...;$kwargs...)::$ret_type)
end

######## an example #########
#############################
struct Iterable{T} <: DuckType{
    Union{
        Behavior{typeof(iterate), Tuple{This, Any}},
        Behavior{typeof(iterate), Tuple{This}}
    },
    Union{}
}
end

function get_return_type(::Type{Iterable{T}}, ::Type{Behavior{typeof(iterate), Tuple{This, Any}}}) where {T}
    return T
end
function Base.iterate(arg1::Guise{Duck, <:Any}) where Duck
    if implies(Duck, Behavior{typeof(iterate), Tuple{This}})
        return iterate(unwrap(arg1))
    end
end
function Base.iterate(arg1::Guise{Duck, <:Any}, arg2) where Duck
    beh = Behavior{typeof(iterate), Tuple{This, Any}}

    return dispatch_required_method(beh, Duck, arg1, arg2)
end

function narrow(::Type{<:Iterable}, ::Type{T}) where T
    E = eltype(T)
    return Iterable{E}
end

struct IsContainer{T} <: DuckType{
    Union{
        Behavior{typeof(length), Tuple{This}},
        Behavior{typeof(getindex), Tuple{This, Int}}
    },
    Union{
        Iterable{T}
    }
}
end

using Test
@testset "basics" begin
    @test implies(IsContainer{Any}, Iterable{Any})
    @test !quacks_like(IsContainer{Any}, IOBuffer)
    @test quacks_like(IsContainer{Any}, Vector{Int})
    @test wrap(IsContainer{Int}, [1,2,3]) isa Guise{IsContainer{Int}, Vector{Int}}
    @test rewrap(wrap(IsContainer{Int}, [1,2,3]), Iterable) isa Guise{Iterable{Int}, Vector{Int}}
    @test find_original_duck_type(IsContainer{Int}, Behavior{typeof(iterate), Tuple{This, Any}}) <: Iterable
end
end
