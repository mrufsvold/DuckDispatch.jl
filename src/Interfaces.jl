"""
An `InterfaceKind` describes the requirements of a kind of interface. For example, the `Indexable`
InterfaceKind requires `getindex(::This, ::Any)`. Each InterfaceKind requires the following:

Optional:
`narrow` for InterfaceKinds with parameters
`_required_methods` for leaf Kinds
"""
abstract type InterfaceKind end

"""
Meet describes the intersection of interfaces. 

A Meet is a binary tree of composed interfaces. Order matters to the identity of the tree because
clashing required method interfaces are overwritten by the later interface.
"""
struct Meet{T<Tuple{<:InterfaceKind, <:Union{Nothing,InterfaceKind}}} <: InterfaceKind end
function Meet(::Type{T}) where T <: InterfaceKind
    return Meet{Tuple{T,Nothing}}()
end
function Meet(::Type{T}, types::Type{<:InterfaceKind}...) where T <: InterfaceKind
    return Meet{Tuple{T,Meet(types)}}()
end

"""
    @Meet(exprs...)
This macro allows you to make a new parametric composite interface. It works like

```
const IsContainer{N, T} = @Meet(Indexable{T}, Sized{N})
```
"""
macro Meet(exprs...)
    return esc(make_meet_expr(exprs...))
end

function make_meet_expr(exprs...)
    if length(exprs) == 1
        return :($Meet{$(exprs[1]), Nothing})
    end
    head_expr, tail_exprs = peel(exprs)
    return :($Meet{$(head_expr), $(make_meet_expr(tail_exprs...))})
end

"""
    implies(::InterfaceKind, ::InterfaceKind)
Returns whether the first interface implies the second interface.
"""
function implies(::Type{<:InterfaceKind}, ::Type{<:Meet})
    return false
end
function implies(::Type{Meet{I, Nothing}}, ::Type{T}) where {I, T<:InterfaceKind}
    T === I && return true
    if I <: Meet
        return implies(I, T)
    end
    return false
end
function implies(::Type{Meet{I, J}}, ::Type{T}) where {I, J, T<:InterfaceKind}
    I === T && return true
    J === T && return true
    return implies(I, T) || implies(J, T)
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

"""
    extract_interface_kind(::Type{Interface})
Return the InterfaceKind of the Interface.
"""
function extract_interface_kind(::Type{Interface{I,<:Any}}) where I
    return I
end

"""Returns all the methods that must be defined to satisfy this interface
This function is created for each InterfaceKind by the macro
"""
function required_methods(::Type{Meet{I, J}}) where {I, J}
    return (required_methods(I)..., required_methods(J)...)
end
function required_methods(::Type{Nothing})
    return ()
end

"""Returns whether the given type meets the requirements of the interface"""
function meets_requirements(::Type{I}, ::Type{T})::Bool where {I<:InterfaceKind,T}
    return all(r -> is_method_implemented(r, T), required_methods(I))
end
function meets_requirements(::Type{Interface{I, <:Any}}, t)::Bool where I
    return meets_requirements(I, t)
end

function is_method_implemented(r::RequiredMethod{F}, ::Type{T}) where {F,T}
    args = replace_interface_with_t(r.arg_types, T)
    Ts = Tuple{args...}
    return hasmethod(F, Ts)
end

function peel_interface_layer(f, ::Type{I}, args...) where {I <: InterfaceKind}
    if hasmethod(f, typeof(args))
        return run(f, I, args)
    end
end
function peel_interface_layer(::Type{I}, arg) where {I <: InterfaceKind}

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



