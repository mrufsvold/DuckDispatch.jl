module R
using JET

struct This end
struct Behavior{F, Sig<:Tuple} end
const NoBehavior = Behavior{Tuple{}}

function get_signature(::Type{Behavior{F, S}}) where {F,S}
    return S
end

function get_func_type(::Type{Behavior{F, S}}) where {F,S}
    return F
end


struct Meet{
    Head, #<:Union{Meet, Behavior}, 
    Tail  #<:Union{Meet, Behavior}
    }
end

function extract_head(::Type{Meet{H, T}}) where {H,T}
    return H
end
function extract_tail(::Type{Meet{H, T}}) where {H,T}
    return T
end

abstract type DuckType{M<:Meet} end

function get_meet(::Type{DuckType{M}}) where M<:Meet
    return M
end

function get_meet(::Type{D}) where D <: DuckType
    return get_meet(supertype(D))
end

function narrow(::Type{T}, ::Any) where {T <: DuckType}
    return T
end

struct Guise{Duck, Data}
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
    # otherwise, we need to recursively check if the Meet identity of the DuckTypes imply composition
    return implies(get_meet(D1), get_meet(D2))
end
# most basic check is whether the signature of the the second behavior is a subtype of the first
function implies(::Type{Behavior{F1, S1}}, ::Type{Behavior{F2, S2}}) where {F1, S1, F2, S2} 
    return F1===F2 && S2 <: S1
end
# All behaviors imply no behavior (no behavior is the base case for the linked list type)
function implies(::Type{<:Behavior}, ::Type{NoBehavior})
    return true
end
# No behavior implies a Meet
function implies(::Type{<:Behavior}, ::Type{<:Meet}) 
    return false
end
# This is the base case for getting a Meet in the first param (NoBehavior means its the end of the list)
function implies(::Type{Meet{Head, NoBehavior}}, ::Type{B}) where {Head, B<:Behavior}
    return implies(Head, B)
end
# When we get a Meet that points to two children, we need to recurse on both
# If either of the children imply the behavior, then the Meet implies the behavior
function implies(::Type{Meet{Head, Tail}}, ::Type{B}) where {Head, Tail, B<:Behavior} 
    return implies(Head, B) || implies(Tail, B)
end
# The most generic case is when we get two Meets:
function implies(::Type{D1}, ::Type{D2}) where {D1<:Meet, D2<:Meet}
    # If we get an exact match between two Meets, we can short-circuit to true
    if D1 === D2
        return true
    end
    # otherwise, we need to check if both the head and tail are implied by the Meet
    return implies(D1, extract_head(D2)) && implies(D1, extract_tail(D2))
end


function quacks_like(::Type{Duck}, ::Type{Data}) where {Duck<:DuckType, Data}
    return quacks_like(get_meet(Duck), Data)
end
function quacks_like(::Type{M}, ::Type{Data}) where {M<:Meet, Data}
    type_checker = TypeChecker{Data}(Data)
    return type_checker(M)
end

struct TypeChecker{Data}
    t::Type{Data}
end
Base.@constprop :aggressive function (::TypeChecker{Data})(::Type{B}) where {Data, B<:Behavior}
    B === NoBehavior && return true
    sig_types = fieldtypes(get_signature(B))::Tuple
    func_type = get_func_type(B)
    replaced = map((x) -> x === This ? Data : x, sig_types)
    return hasmethod(func_type.instance, replaced)
end

function get_behaviors(first_meet::Type{<:Meet})
    behaviors = Type{<:Behavior}[]
    stack = Type{<:Meet}[]
    push!(stack, first_meet)
    while true
        meet = pop!(stack)
        head = extract_head(meet)
        tail = extract_tail(meet)
        head <: Meet && push!(stack, head)
        tail <: Meet && push!(stack, tail)
        head <: Behavior && !(head <: NoBehavior) && push!(behaviors, head)
        tail <: Behavior && !(tail <: NoBehavior) && push!(behaviors, tail)
        length(stack) == 0 && break
    end
    return behaviors
end

@generated function (type_checker::TypeChecker)(::Type{M}) where {M<:Meet}
    behavior_stream = get_behaviors(M)
    check_quotes = Expr[
        :(type_checker($behavior) || return false)
        for behavior in behavior_stream
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
    Meet{
    Meet{Behavior{typeof(iterate), Tuple{This, Any}}, NoBehavior},
    Meet{Behavior{typeof(iterate), Tuple{This}}, NoBehavior}
}
}
end

function get_return_type(::Type{Iterable{T}}, ::B) where {T, B<:Behavior}
    
end
function Base.iterate(g::Guise{Duck, <:Any}) where Duck
    if implies(Duck, Behavior{Tuple{typeof(iterate), This}})
        return iterate(unwrap(g))
    end
end
function Base.iterate(g::Guise{Duck, <:Any}, state) where Duck
    if implies(Duck, Behavior{Tuple{typeof(iterate), This, Any}})
        return iterate(unwrap(g), state)
    end
end

function narrow(::Type{<:Iterable}, ::Type{T}) where T
    E = eltype(T)
    return Iterable{E}
end

struct IsContainer{T} <: DuckType{
    Meet{
    Meet{Behavior{typeof(getindex), Tuple{This, Any}}, NoBehavior},
    get_meet(Iterable)
}
}
end

using Test
@testset "basics" begin
    @test implies(IsContainer, Iterable)
    @test !quacks_like(IsContainer, Int)
    @test quacks_like(IsContainer, Vector{Int})
    @test wrap(IsContainer{Int}, [1,2,3]) isa Guise{IsContainer{Int}, Vector{Int}}
    @test rewrap(wrap(IsContainer{Int}, [1,2,3]), Iterable) isa Guise{Iterable{Int}, Vector{Int}}
end
end
