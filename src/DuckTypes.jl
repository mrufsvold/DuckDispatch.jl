"""
An `DuckType` describes the requirements of a kind of interface. For example, the `Indexable`
DuckType requires `getindex(::This, ::Any)`. Each DuckType requires the following:

Optional:
`narrow` for DuckTypes with parameters
`_required_methods` for leaf Kinds
"""
abstract type DuckType end

"""This is a placeholder type for generically referring to the current
interface so that inheriting interfaces still make sense"""
struct This <: DuckType end

"""
Meet describes the intersection of interfaces. 

A Meet is a binary tree of composed interfaces. Order matters to the identity of the tree because
clashing required method interfaces are overwritten by the later interface.
"""
struct Meet{T<Tuple{<:DuckType, <:Union{Nothing,DuckType}}} <: DuckType end
function Meet(::Type{T}) where T <: DuckType
    return Meet{Tuple{T,Nothing}}()
end
function Meet(::Type{T}, types::Type{<:DuckType}...) where T <: DuckType
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
"""
    make_meet_expr(exprs...)
Recursively build Meet type expressions
"""
function make_meet_expr(exprs...)
    if length(exprs) == 1
        return :($Meet{$(exprs[1]), Nothing})
    end
    head_expr, tail_exprs = peel(exprs)
    return :($Meet{$(head_expr), $(make_meet_expr(tail_exprs...))})
end


"""
    implies(::DuckType, ::DuckType)
Returns whether the first DuckType implies the second DuckType.
"""
function implies(::Type{<:DuckType}, ::Type{<:Meet})
    return false
end
function implies(::Type{Meet{I, Nothing}}, ::Type{T}) where {I, T<:DuckType}
    T === I && return true
    if I <: Meet
        return implies(I, T)
    end
    return false
end
function implies(::Type{Meet{I, J}}, ::Type{T}) where {I, J, T<:DuckType}
    I === T && return true
    J === T && return true
    return implies(I, T) || implies(J, T)
end
function implies(::Type, ::Type)
    return true
end

"""
    implies(::Type{Tuple}, ::Type{Tuple})

Returns whether each element of the first tuple implies the corresponding element of the second tuple.
"""
function implies(::Type{SigT}, ::Type{ArgT}) where {SigT<:Tuple, ArgT<:Tuple}
    sig_types = fieldtypes(SigT)
    arg_types = fieldtypes(ArgT)

    length(sig_types) != length(arg_types) && return false

    return all(map(implies, sig_types, arg_types))
end

