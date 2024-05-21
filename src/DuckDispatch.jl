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

    function DuckDispatch.get_return_type(::Type{Iterable{T}},
            ::Type{DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This, Any}}}) where {T}
        return Tuple{T, <:Any}
    end
    function DuckDispatch.get_return_type(::Type{Iterable{T}},
            ::Type{DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This}}}) where {T}
        return Tuple{T, <:Any}
    end
    function Base.iterate(arg1::DuckDispatch.Guise{DuckT, <:Any}) where {DuckT}
        return DuckDispatch.dispatch_behavior(
            DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This}},
            arg1
        )
    end
    function Base.iterate(arg1::DuckDispatch.Guise{Iterable{T}}) where {T}
        return DuckDispatch.run_behavior(iterate, arg1)
    end
    function Base.iterate(arg1::DuckDispatch.Guise{DuckT, <:Any}, arg2) where {DuckT}
        return DuckDispatch.dispatch_behavior(
            DuckDispatch.Behavior{typeof(iterate), Tuple{DuckDispatch.This, Any}},
            arg1
        )
    end
    function Base.iterate(arg1::DuckDispatch.Guise{Iterable{T}}, arg2::Any) where {T}
        return DuckDispatch.run_behavior(iterate, arg1, arg2)
    end

    function DuckDispatch.narrow(::Type{<:Iterable}, ::Type{T}) where {T}
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
    @test DuckDispatch.wrap(IsContainer{Int}, [1, 2, 3]) isa
          DuckDispatch.Guise{IsContainer{Int}, Vector{Int}}
    @test DuckDispatch.rewrap(DuckDispatch.wrap(IsContainer{Int}, [1, 2, 3]), Iterable) isa
          DuckDispatch.Guise{Iterable{Int}, Vector{Int}}
    @test DuckDispatch.find_original_duck_type(
        IsContainer{Int}, DuckDispatch.Behavior{
            typeof(iterate), Tuple{DuckDispatch.This, Any}}) <: Iterable
    @test iterate(DuckDispatch.wrap(Iterable{Int}, [1, 2, 3])) == (1, 2)
    @test iterate(DuckDispatch.wrap(IsContainer{Int}, [1, 2, 3])) == (1, 2)
end

end
