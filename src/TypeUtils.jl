"""
    `get_top_level_behaviors(::Type{<:DuckType}) -> Union{Behavior...}`
Returns the top level behaviors of a `DuckType` (specifically, the behaviors that 
the `DuckType` implements directly).
"""
function get_top_level_behaviors(::Type{D}) where {D <: DuckType}
    sup = supertype(D)
    sup === Any && return extract_behaviors(D)
    return get_top_level_behaviors(sup)
end
# helper function to extract the behaviors from the abstract DuckType
extract_behaviors(::Type{DuckType{B, D}}) where {B, D} = B

"""
    `get_duck_types(::Type{<:DuckType}) -> Union{DuckType...}`
Returns the duck types that a `DuckType` is composed of.
"""
function get_duck_types(::Type{D}) where {D <: DuckType}
    sup = supertype(D)
    sup === Any && return extract_duck_types(D)
    return get_duck_types(sup)
end
# helper function to extract the duck types from the abstract DuckType
extract_duck_types(::Type{DuckType{B, D}}) where {B, D} = D

"""
    `all_behaviors_of(::Type{D}) -> Tuple{Behavior...}`
Returns all the behaviors that a `DuckType` implements, including those of its composed `DuckTypes`.
"""
function all_behaviors_of(::Type{D}) where {D <: DuckType}
    return tuple_collect(behaviors_union(D))
end

# helper function for behaviors_union
function _behaviors_union(::Type{D}) where {D}
    this_behavior_union = get_top_level_behaviors(D)
    these_duck_types = tuple_collect(get_duck_types(D))
    length(these_duck_types) == 0 && return this_behavior_union
    return Union{this_behavior_union, _behaviors_union(these_duck_types...)}
end
"""
    `behaviors_union(::Type{D}) -> Union{Behavior...}`
Returns the union of all the behaviors that a `DuckType` implements, including those of its composed `DuckTypes`.
"""
@generated function behaviors_union(::Type{D}) where {D}
    u = _behaviors_union(D)
    return :($u)
end

"""
    implies(::Type{DuckType}, ::Type{DuckType}})
Return true if the first DuckType is a composition that contains the second DuckType.
"""
function implies(::Type{D1}, ::Type{D2}) where {D1 <: DuckType, D2 <: DuckType}
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
    return F1 === F2 && S2 <: S1
end
function implies(::Type{T1}, ::Type{T2}) where {T1, T2}
    return T2 <: T1
end
function implies(t1::Tuple, t2::Tuple)
    length(t1) != length(t2) && return false
    return tuple_all(implies, t1, t2)
end

"""
    `find_original_duck_type(::Type{D}, ::Type{B}) -> Union{Nothing, DataType}`
Returns the DuckType that originally implemented a behavior `B` in the DuckType `D`.
This allows us to take a `DuckType` which was composed of many others, find the original,
and then rewrap to that original type.
"""
@generated function find_original_duck_type(::Type{D}, ::Type{B}) where {D, B}
    these_behaviors = tuple_collect(get_top_level_behaviors(D))
    res = if any(implies(b, B) for b in these_behaviors)
        D
    end
    for dt in tuple_collect(get_duck_types(D))
        child_res = find_original_duck_type(dt, B)::Union{Nothing, DataType}
        if !isnothing(child_res)
            res = child_res
        end
    end
    return :($res)
end

"""
    `quacks_like(DuckT, Data) -> Bool`
Checks if `Data` implements all required `Behavior`s of `DuckT`.
"""
function quacks_like(::Type{DuckT}, ::Type{Data}) where {DuckT <: DuckType, Data}
    narrowed = narrow(DuckT, Data)
    return _quacks_like(narrowed, Data)
end
@generated function _quacks_like(
        ::Type{DuckT}, ::Type{Data}) where {DuckT <: DuckType, Data}
    type_checker = TypeChecker(Data)
    behavior_list = all_behaviors_of(DuckT)
    check_quotes = Expr[
                        :($type_checker($b) || return false)
                        for b in behavior_list
                        ]
    return Expr(:block, check_quotes..., :(return true))
end
function quacks_like(::Type{T}, ::Type{Data}) where {T, Data}
    return Data <: T
end
function quacks_like(::Type{G}, ::Type{Data}) where {G <: Guise, Data}
    DuckT = get_duck_type(G)
    narrow_duck_type = narrow(DuckT, Data)
    return quacks_like(narrow_duck_type, Data)
end

"""
    `wrap(::Type{DuckT}, data::T) -> Guise{DuckT, T}`
Wraps an object of type `T` in a `Guise` that implements the `DuckType` `DuckT`.
"""
function wrap(::Type{DuckT}, data::T) where {DuckT <: DuckType, T}
    NarrowDuckType = narrow(DuckT, T)::Type{<:DuckT}
    quacks_like(NarrowDuckType, T) && return Guise{NarrowDuckType, T}(NarrowDuckType, data)
    error("Type $T does not implement the methods required by $NarrowDuckType")
end

"""
    `unwrap(g::Guise) -> Any`
Returns the data wrapped in a `Guise`.
"""
unwrap(x::Guise) = x.data
unwrap(x) = x

"""
    `rewrap(g::Guise{Duck1, <:Any}, ::Type{Duck2}) -> Guise{Duck2, <:Any}`
Rewraps a `Guise` to implement a different `DuckType`.
"""
rewrap(x::Guise{I1, <:Any}, ::Type{I2}) where {I1, I2 <: DuckType} = wrap(I2, unwrap(x))

@generated function wrap_if_this(::Type{T}, ::Type{D}, arg) where {T, D}
    T === This && return :(rewrap(arg, D))
    return :(arg)
end

@generated function rewrap_where_this(
        ::Type{T}, ::Type{D}, args::Tuple) where {D <: DuckType, T <: Tuple}
    fields = static_fieldtypes(T)
    duck_types = tuple((D for _ in fields)...)
    return :(tuple_map(wrap_if_this, $fields, $duck_types, args))
end
