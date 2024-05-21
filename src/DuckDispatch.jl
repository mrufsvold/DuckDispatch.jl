module DuckDispatch

if VERSION >= v"1.11"
public 
    Guise,
    DuckType,
    This,
    narrow,
    wrap,
    unwrap,
    rewrap
end

@static if false
    macro test end
    macro test_throws end
end

using BangBang: append!!#, push!!
# using Base: tail
using TestItems: @testitem
# using SumTypes: @sum_type, @cases
using ExproniconLite: JLFunction, JLStruct, is_function, xcall, codegen_ast

include("Utils.jl")
include("Types.jl")
include("TypeUtils.jl")
include("BehaviorDispatch.jl")

@testitem "Test Basics" begin
    struct Iterable{T} <: DuckDispatch.DuckType{
        Union{
            DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This, Any}},
            DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This}}
        },
        Union{}
    }
    end
    
    function get_return_type(::Type{Iterable{T}}, ::Type{DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This, Any}}}) where {T}
        return T
    end
    function Base.iterate(arg1::DuckDispatch.Guise{DuckT, <:Any}) where DuckT
        if DuckDispatch.implies(DuckT, DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This}})
            return iterateDuckDispatch.(unwrap(arg1))
        end
    end
    function Base.iterate(arg1::DuckDispatch.Guise{DuckT, <:Any}, arg2) where DuckT
        beh = DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This, Any}}
    
        return dispatch_required_method(beh, DuckT, arg1, arg2)
    end
    
    function DuckDispatch.narrow(::Type{<:Iterable}, ::Type{T}) where T
        E = eltype(T)
        return Iterable{E}
    end
    
    struct IsContainer{T} <: DuckDispatch.DuckType{
        Union{
            DuckDispatch.Behavior{typeof(length), Tuple{DuckDispatch.This}},
            DuckDispatch.Behavior{typeof(getindex), Tuple{DuckDispatch.This, Int}}
        },
        Union{
            Iterable{T}
        }
    }
    end
    
    @test DuckDispatch.implies(IsContainer{Any}, Iterable{Any})
    @test !DuckDispatch.quacks_like(IsContainer{Any}, IOBuffer)
    @test DuckDispatch.quacks_like(IsContainer{Any}, Vector{Int})
    @test DuckDispatch.wrap(IsContainer{Int}, [1,2,3]) isa DuckDispatch.Guise{IsContainer{Int}, Vector{Int}}
    @test DuckDispatch.rewrap(DuckDispatch.wrap(IsContainer{Int}, [1,2,3]), Iterable) isa DuckDispatch.Guise{Iterable{Int}, Vector{Int}}
    @test DuckDispatch.find_original_duck_type(IsContainer{Int}, DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This, Any}}) <: Iterable
end


end
