module DuckDispatch

export This, @duck_type, @duck_dispatch
if VERSION >= v"1.11"
    public
    Guise,
    DuckType,
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
using Tricks: static_fieldtypes, static_methods, static_hasmethod

include("Utils.jl")
include("Types.jl")
include("TypeUtils.jl")
include("BehaviorDispatch.jl")
include("MethodDispatch.jl")
include("DuckTypeMacro.jl")
include("PrettyPrinting.jl")

@testitem "Test Basics" begin
    DuckDispatch.@duck_type struct Iterable{T}
        function Base.iterate(::DuckDispatch.This)::Union{Nothing, Tuple{T, <:Any}} end
        function Base.iterate(::DuckDispatch.This, ::Any)::Union{Nothing, Tuple{T, <:Any}} end
        @narrow T -> Iterable{eltype(T)}
    end
    @duck_dispatch function my_collect(arg1::Iterable{T}) where {T}
        v = T[]
        for x in arg1
            push!(v, x)
        end
        return v
    end

    @test my_collect((1, 2)) == [1, 2]
    @test my_collect(1:2) == [1, 2]
    @test my_collect((i for i in 1:2)) == [1, 2]

    """
    `IsContainer{T}` is a duck type that requires `T` to be an iterable and indexible type of a finite length.
    """
    DuckDispatch.@duck_type struct IsContainer{T} <: Union{Iterable{T}}
        function Base.length(::DuckDispatch.This)::Int end
        function Base.getindex(::DuckDispatch.This, ::Any)::T end
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

    DuckDispatch.@duck_dispatch function my_collect(arg1::IsContainer{T}) where {T}
        return T[x for x in arg1]
    end
    @test my_collect((1, 2)) == [1, 2]

    ch = Channel{Int}() do ch
        for i in 1:2
            put!(ch, i)
        end
    end

    DuckDispatch.@duck_dispatch function container_collect(arg1::IsContainer{T}) where {T}
        return T[x for x in arg1]
    end
    @test_throws MethodError container_collect(ch)

    DuckDispatch.@duck_dispatch function bad_index(arg1::Iterable{T}, arg2) where {T}
        return arg1[arg2]
    end
    @test_throws DuckDispatch.MissingBehaviorCall bad_index([1,2], :a)
end

end
