abstract type InterfaceKind end

"""
Meet describes the intersection of multiple interfaces. 

"""
struct Meet{T<:NTuple{<:Any, InterfaceKind}} <: InterfaceKind end
function Meet(types::InterfaceKind...)
    return Meet{Tuple{types...}}
end

"""
    narrow(::Type{T}, ::Any) where {T <: InterfaceKind}
A function which the user can overload to specify the most narrow type of InterfaceKind
that can wrap the type of data.

Note that the dispatch for this function must overload in the type domain. Meaning that
the signature should look like `narrow(::Type{MyInterface}, ::Type{D}) where D`.
"""
function narrow(::Type{T}, ::Any) where {T <: InterfaceKind}
    return T
end

"""
    Interface{I<:InterfaceKind,T}
An wrapper for a specific InterfaceKind around a specific type of data (`T`)
"""
struct Interface{I<:InterfaceKind,T}
    data::T
end

struct GenericWrap end

"""This is a placeholder type for generically referring to the current
interface so that inheriting interfaces still make sense"""
struct This <: InterfaceKind end

"""
    RequiredMethod 
# Holds the information about a method that is required by an interface. 
"""
struct RequiredMethod{F}
    arg_types::DataType
end

"""
    wrap(<:InterfaceKind, data)
Check that the type of data satisfies the interface. Wrap the data in an Interface. 
"""
function wrap(::Type{I}, d::T) where {I<:InterfaceKind,T}
    narrow_I = narrow(I, T)::Type{<:I}
    meets_requirements(narrow_I, T) && return Interface{narrow_I,T}(d)
    error("$T does not implement the interface $narrow_I")
end

function wrap(::GenericWrap, ::Type{I}, d::T) where {I<:InterfaceKind,T}
    meets_requirements(I, T) && return Interface{I,Any}(d)
    error("$T does not implement the interface $I")
end

"""
    unwrap(::Interface)
Return the data wrapped in the Interface.
"""
function unwrap(x::Interface)
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
    rewrap(<:Interface, <:InterfaceKind)
Rewrap the data from the Interface in a new Interface for the new given Interface.
"""
function rewrap(x::Interface{I1,<:Any}, ::Type{I2}) where {I1,I2<:InterfaceKind}
    I1 == I2 && return x
    return wrap(I2, unwrap(x))
end
function rewrap(::Type{OldInterface}, ::Type{NewInterface}, args) where {OldInterface, NewInterface}
    head, tail = peel(args)
    head_interface_type = extract_interface_kind(head)
    rewrap_head = if head_interface_type <: OldInterface
        head = rewrap(head, NewInterface)
    else
        head
    end
    return (rewrap_head, rewrap(OldInterface, NewInterface, tail)...)
end
function rewrap(::Type{OldInterface}, ::Type{NewInterface}, ::Tuple{}) where {OldInterface, NewInterface}
    return ()
end

function extract_interface_kind(::Type{Interface{I,<:Any}}) where I
    return I
end

"""
    get_return_type(<:InterfaceKind, ::typeof(F))
gets the return type of function F for the given InterfaceKind.
"""
function get_return_type end

"""Returns the list of interfaces that are required to use this interface"""
function required_interfaces(::Type{T}) where T <: InterfaceKind
    return ()
end

"""Returns all the methods that must be defined to satisfy this interface"""
function required_methods(::Type{I}) where {I<:InterfaceKind}
    these_methods = _required_methods(I)

    req_interfaces = required_interfaces(I)
    length(req_interfaces) == 0 && return these_methods

    methods_for_req_interfaces = map(required_methods, req_interfaces)
    all_methods_nested = push!!(methods_for_req_interfaces, these_methods)
    all_methods = reduce(append!!, all_methods_nested)
    return all_methods
end

"""Internal function that returns only the methods that are required for this interface
and not its children"""
function _required_methods(::T) where T <: InterfaceKind 
    return _required_methods(T)
end

"""Returns whether the given type meets the requirements of the interface"""
function meets_requirements(::Type{I}, ::Type{T})::Bool where {I<:InterfaceKind,T}
    return all(r -> is_method_implemented(r, T), required_methods(I))
end
function meets_requirements(::Type{Meet{I}}, ::Type{T}) where {I, T}
    constituent_interface_kinds = fieldtypes(I)
    return all(meets_requirements.(constituent_interface_kinds, T))
end
function meets_requirements(::Type{Interface{I, <:Any}}, t)::Bool where I
    return meets_requirements(I, t)
end

function is_method_implemented(r::RequiredMethod{F}, ::Type{T}) where {F,T}
    args = replace_interface_with_t(r.arg_types, T)
    return length(methods(F, args)) > 0
end

"""
    run(f, args)
This method is called by all methods that are defined for an interface.
It manages unwrapping all the interfaces in the arguments.
"""
function run(f, args)
    unwrapped_args = unwrap(args)
    return f(unwrapped_args...)
end

@testitem "Basic interface wrapping test" begin
    struct HasEltype{T} <: InterfaceDispatch.InterfaceKind end
    InterfaceDispatch._required_methods(::Type{HasEltype{T}}) where {T} = (
        InterfaceDispatch.RequiredMethod{eltype}(Tuple{InterfaceDispatch.This}),
        )
    struct IsIterable{T} <: InterfaceDispatch.InterfaceKind end
    InterfaceDispatch._required_methods(::Type{IsIterable{T}}) where {T} = (
        InterfaceDispatch.RequiredMethod{iterate}(Tuple{InterfaceDispatch.This}),
        InterfaceDispatch.RequiredMethod{iterate}(Tuple{InterfaceDispatch.This, Any}),
        )
    
    InterfaceDispatch.required_interfaces(::Type{IsIterable{T}}) where {T} = (HasEltype{T},)
    
    # Here we check that we correctly fail when trying to wrap a type which does not adhere to the interface.
    @test !InterfaceDispatch.is_method_implemented(
        InterfaceDispatch.RequiredMethod{iterate}(Tuple{InterfaceDispatch.This}), 
        Nothing
        )
    @test_throws ErrorException InterfaceDispatch.wrap(IsIterable{Int}, nothing)
    
    interface = InterfaceDispatch.wrap(HasEltype{Int}, [1, 2])
    @test interface isa InterfaceDispatch.Interface{HasEltype{Int},Vector{Int}}
    @test InterfaceDispatch.unwrap(interface) == ([1, 2])
    @test InterfaceDispatch.rewrap(interface, IsIterable{Int}) isa InterfaceDispatch.Interface{IsIterable{Int},Vector{Int}}
end



