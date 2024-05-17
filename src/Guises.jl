"""
    Guise{I<:DuckType,T}
An wrapper for a specific DuckType around a specific type of data (`T`)
"""
struct Guise{I<:DuckType,T}
    data::T
end

"""
GenericWrap is a trait for dispatching the Guise constructor to 
hide the type of the internal data with `Any`.
"""
struct GenericWrap end


"""
    RequiredMethod 
# Holds the information about a method that is required by an interface. 
"""
struct RequiredMethod{F}
    arg_types::DataType
end

"""
    wrap(<:DuckType, data)
Check that the type of data satisfies the interface. Wrap the data in an Guise. 
"""
function wrap(::Type{I}, d::T) where {I<:DuckType,T}
    narrow_I = narrow(I, T)::Type{<:I}
    meets_requirements(narrow_I, T) && return Guise{narrow_I,T}(d)
    error("$T does not implement the interface $narrow_I")
end

function wrap(::GenericWrap, ::Type{I}, d::T) where {I<:DuckType,T}
    meets_requirements(I, T) && return Guise{I,Any}(d)
    error("$T does not implement the interface $I")
end

"""
    unwrap(::Guise)
Return the data wrapped in the Guise.
"""
function unwrap(x::Guise)
    return x.data
end
function unwrap(x)
    return x
end
function unwrap(xs::Tuple)
    head, tail = peel(xs)
    return (unwrap(head), unwrap(tail)...)
end
function unwrap(::Tuple{})
    return ()
end

"""
    rewrap(<:Guise, <:DuckType)
Rewrap the data from the Guise in a new Guise for the new given Guise.
"""
function rewrap(x::Guise{I1,<:Any}, ::Type{I2}) where {I1,I2<:DuckType}
    return wrap(I2, unwrap(x))
end
function rewrap(::Type{OldGuise}, ::Type{NewGuise}, args) where {OldGuise, NewGuise}
    head, tail = peel(args)
    head_interface_type = extract_interface_kind(head)
    rewrap_head = if head_interface_type <: OldGuise
        head = rewrap(head, NewGuise)
    else
        head
    end
    return (rewrap_head, rewrap(OldGuise, NewGuise, tail)...)
end
function rewrap(::Type{OldGuise}, ::Type{NewGuise}, ::Tuple{}) where {OldGuise, NewGuise}
    return ()
end

"""
    extract_interface_kind(::Type{Guise})
Return the DuckType of the Guise.
"""
function extract_interface_kind(::Type{Guise{I,<:Any}}) where I
    return I
end

"""Returns all the methods that must be defined to satisfy this interface
This function is created for each DuckType by the macro
"""
function required_methods(::Type{Meet{I, J}}) where {I, J}
    return (required_methods(I)..., required_methods(J)...)
end
function required_methods(::Type{Nothing})
    return ()
end

"""Returns whether the given type meets the requirements of the interface"""
function meets_requirements(::Type{I}, ::Type{T})::Bool where {I<:DuckType,T}
    return all(r -> is_method_implemented(r, T), required_methods(I))
end
function meets_requirements(::Type{Guise{I, <:Any}}, t)::Bool where I
    return meets_requirements(I, t)
end

function is_method_implemented(r::RequiredMethod{F}, ::Type{T}) where {F,T}
    args = replace_interface_with_t(r.arg_types, T)
    Ts = Tuple{args...}
    return hasmethod(F, Ts)
end

function peel_interface_layer(f, ::Type{I}, args...) where {I <: DuckType}
    if hasmethod(f, typeof(args))
        return run(f, I, args)
    end
end
function peel_interface_layer(::Type{I}, arg) where {I <: DuckType}

end

"""
    run(f, args)
This method is called by all methods that are defined for an interface.
It manages unwrapping all the interfaces in the arguments.
"""
function run(f, ::Type{I}, args)
    
    unwrapped_args = unwrap(args)
    return f(unwrapped_args...)
end

@testitem "Basic interface wrapping test" begin
    struct HasEltype{T} <: DuckDispatch.DuckType end
    DuckDispatch._required_methods(::Type{HasEltype{T}}) where {T} = (
        DuckDispatch.RequiredMethod{eltype}(Tuple{DuckDispatch.This}),
        )
    struct IsIterable{T} <: DuckDispatch.DuckType end
    DuckDispatch._required_methods(::Type{IsIterable{T}}) where {T} = (
        DuckDispatch.RequiredMethod{iterate}(Tuple{DuckDispatch.This}),
        DuckDispatch.RequiredMethod{iterate}(Tuple{DuckDispatch.This, Any}),
        )
    
    DuckDispatch.required_interfaces(::Type{IsIterable{T}}) where {T} = (HasEltype{T},)
    
    # Here we check that we correctly fail when trying to wrap a type which does not adhere to the interface.
    @test !DuckDispatch.is_method_implemented(
        DuckDispatch.RequiredMethod{iterate}(Tuple{DuckDispatch.This}), 
        Nothing
        )
    @test_throws ErrorException DuckDispatch.wrap(IsIterable{Int}, nothing)
    
    interface = DuckDispatch.wrap(HasEltype{Int}, [1, 2])
    @test interface isa DuckDispatch.Guise{HasEltype{Int},Vector{Int}}
    @test DuckDispatch.unwrap(interface) == ([1, 2])
    @test DuckDispatch.rewrap(interface, IsIterable{Int}) isa DuckDispatch.Guise{IsIterable{Int},Vector{Int}}
end



