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

# This makes VSCode missing symbol warnings happy
@static if false
    macro test end
    macro test_throws end
end

# using Base: tail
using TestItems: @testitem
using SumTypes: @sum_type, @cases
using ExproniconLite: JLFunction, JLStruct, is_function, codegen_ast

include("Utils.jl")
include("Types.jl")
include("TypeUtils.jl")
include("BehaviorDispatch.jl")
include("MethodDispatch.jl")
include("DuckTypeMacro.jl")

@testitem "Test Basics" begin
    DuckDispatch.@duck_type struct Iterable{T}
        function Base.iterate(::DuckDispatch.This)::Union{Nothing, Tuple{T, <:Any}} end
        function Base.iterate(::DuckDispatch.This, ::Any)::Union{Nothing, Tuple{T, <:Any}} end
        @narrow T -> Iterable{eltype(T)}
    end

    DuckDispatch.@duck_type struct IsContainer{T} <: Union{Iterable{T}}
        function Base.length(::DuckDispatch.This)::Int end
        function Base.getindex(::DuckDispatch.This, ::Int)::T end
        @narrow T -> IsContainer{eltype(T)}
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
    @test length(DuckDispatch.wrap(IsContainer{Int}, [1, 2, 3])) == 3

    DuckDispatch.@duck_dispatch function collect_ints(arg1::IsContainer{T}) where {T}
        return T[x for x in arg1]
    end
    @test collect_ints((1, 2)) == [1, 2]
end

end
