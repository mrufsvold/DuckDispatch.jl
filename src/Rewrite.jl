module R
using JET
using ExproniconLite
using BangBang: append!!

struct This end

struct Behavior{F, Sig<:Tuple} end

get_signature(::Type{Behavior{F,S}}) where {F,S} = S
get_func_type(::Type{Behavior{F,S}}) where {F,S} = F

abstract type DuckType{Behaviors, DuckTypes} end

narrow(::Type{T}, ::Any) where {T <: DuckType} = T

function get_top_level_behaviors(::Type{D}) where D<:DuckType
    sup = supertype(D)
    sup === Any && return extract_behaviors(D)
    return get_top_level_behaviors(sup)
end
extract_behaviors(::Type{DuckType{B,D}})  where {B,D} = B
function get_duck_types(::Type{D}) where D<:DuckType
    sup = supertype(D)
    sup === Any && return extract_duck_types(D)
    return get_duck_types(sup)
end
extract_duck_types(::Type{DuckType{B,D}}) where {B,D} = D

function all_behaviors_of(::Type{D}) where D <: DuckType
    return tuple_collect(behaviors_union(D))
end

@generated function tuple_collect(::Type{U}) where U
    U === Union{} && return ()
    types = tuple(Base.uniontypes(U)...)
    call = xcall(tuple, types...)
    return codegen_ast(call)
end
function _behaviors_union(::Type{D}) where D 
    this_behavior_union = get_top_level_behaviors(D)
    these_duck_types = tuple_collect(get_duck_types(D))
    length(these_duck_types) == 0 && return this_behavior_union
    return Union{this_behavior_union, _behaviors_union(these_duck_types...)}
end
@generated function behaviors_union(::Type{D}) where D 
    u = _behaviors_union(D)
    return :($u)
end

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


struct Guise{DuckT, Data}
    data::Data
end

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

struct TypeChecker{Data}
    t::Type{Data}
end
function (::TypeChecker{Data})(::Type{B}) where {Data, B<:Behavior}
    sig_types = fieldtypes(get_signature(B))::Tuple
    func_type = get_func_type(B)
    replaced = map((x) -> x === This ? Data : x, sig_types)
    return hasmethod(func_type.instance, replaced)
end

@generated function quacks_like(::Type{Duck}, ::Type{Data}) where {Duck<:DuckType, Data}
    type_checker = TypeChecker{Data}(Data)
    behavior_list = all_behaviors_of(Duck)
    check_quotes = Expr[
        :($type_checker($b) || return false)
        for b in behavior_list
    ]
    return Expr(:block, check_quotes..., :(return true))
end

function wrap(::Type{Duck}, data::T) where {Duck<:DuckType, T}
    NarrowDuckType = narrow(Duck, T)::Type{<:Duck}
    quacks_like(NarrowDuckType, T) && return Guise{NarrowDuckType,T}(data)
    error("Type $T does not implement the methods required by $NarrowDuckType")
end
unwrap(x::Guise) = x.data
rewrap(x::Guise{I1, <:Any}, ::Type{I2}) where {I1, I2<:DuckType} = wrap(I2, unwrap(x))


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
