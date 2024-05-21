module R
using JET
using ExproniconLite
using BangBang: append!!

struct This end
struct Behavior{F, Sig<:Tuple} end

function get_signature(::Type{Behavior{F,S}}) where {F,S}
    return S
end

function get_func_type(::Type{Behavior{F,S}}) where {F,S}
    return F
end

abstract type DuckType{Behaviors} end

function get_behaviors(::Type{D}) where D<:DuckType
    sup = supertype(D)
    if sup === Any
        return extract_behaviors(D)
    end
    return get_behaviors(sup)
end
function extract_behaviors(::Type{DuckType{B}}) where {B}
    return B
end

function behaviors(::Type{D}) where D 
    if D <: Behavior
        return (D,)
    end
    these_behaviors = tuple_collect(get_behaviors(D))
    return mapreduce(behaviors, append!!, these_behaviors)
end
function behaviors_union(::Type{D}) where D 
    behavior_list = behaviors(D)
    return Union{behavior_list...}
end

extract_type(::Type{T}) where T = T
@generated function tuple_collect(::Type{U}) where U
    types = tuple(Base.uniontypes(U)...)
    call = xcall(tuple, types...)
    return codegen_ast(call)
end

function narrow(::Type{T}, ::Any) where {T <: DuckType}
    return T
end

struct Guise{DuckT, Data}
    data::Data
end

function get_duck_type(::Type{Guise{D, <:Any}}) where {D}
    return D
end

"""
    implies(::Type{DuckType}, ::Type{DuckType}})
Return true if the first DuckType is a composition that contains the second DuckType.
"""
function implies(::Type{D1}, ::Type{D2}) where {D1<:DuckType, D2<:DuckType}
    # If we get an exact match between two DuckTypes, we can short-circuit to true
    if D1 === D2
        return true
    end
    # We can also check all the behaviors of D2 and see if they are in the union of
    # behaviors for D1. First, we try to just use the type system to check if D2 <: D1
    behaviors_union(D2) <: behaviors_union(D1) && return true
    
    # If that fails, we need to check the behaviors of D2 one by one
    d1_behaviors = behaviors(D1)
    for b2 in behaviors(D2)
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
    behavior_list = behaviors(Duck)
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

function unwrap(x::Guise)
    return x.data
end

function rewrap(x::Guise{I1, <:Any}, ::Type{I2}) where {I1, I2<:DuckType}
    return wrap(I2, unwrap(x))
end


# an example
struct Iterable{T} <: DuckType{
    Union{
        Behavior{typeof(iterate), Tuple{This, Any}},
        Behavior{typeof(iterate), Tuple{This}}
    }
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

function dispatch_required_method(beh::Type{Behavior{F, S}}, ::Type{Duck}, args...) where {F, S, Duck}
    target_duck_type = check_for_fitting_duck_type(Duck, beh)
    if isnothing(target_duck_type)
        error("No fitting iterate method found for $Duck")
    end
    return F.instance(unwrap_where_this(S, args)...)::get_return_type(target_duck_type, beh)
end

function unwrap_where_this(sig::Type{<:Tuple}, args::Tuple)
    return map(sig, args) do (T, arg)
        T === This ? unwrap(arg) : arg
    end
end

function check_for_fitting_duck_type(::Type{Duck}, ::Type{B}) where {Duck, B}
    # descend through Meets tracking the DuckType that created that meet
    # if we find a fitting Behavior, return the DuckType that created that meet
end

function narrow(::Type{<:Iterable}, ::Type{T}) where T
    E = eltype(T)
    return Iterable{E}
end

struct IsContainer{T} <: DuckType{
    Union{
        Behavior{typeof(length), Tuple{This}},
        Behavior{typeof(getindex), Tuple{This, Int}},
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
end
end


module mwe
abstract type Abstract{T} end
struct StaticConcrete
struct Concrete{A,B} <: Abstract{Abstract{B}} end

function get_T(::Type{X}) where X <: Abstract
    sup = supertype(X)
    if sup === Any
        return extract_T(X)
    end
    return get_T(sup)
end
function extract_T(::Type{Abstract{T}}) where T
    return T
end

@show get_T(Concrete)
end