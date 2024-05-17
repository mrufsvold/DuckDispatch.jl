"""
    replace_interface_with_t(arg_types, ::Type{T})
For each instance of `This` in the list of arg_types, replace with T.
"""
function replace_interface_with_t(arg_types::Tuple, ::Type{T}) where {T}
    # base case
    if length(arg_types) == 0
        return ()
    end

    # split the arg types we have
    H, arg_tail = peel(arg_types)
    # replace This
    head_type = H <: This ? T : H

    # recurse
    tail_types = replace_interface_with_t(arg_tail, T)

    return (head_type, tail_types...)
end
# turns tuple type into a tuple of types and back again so that the recursive function above
# can do its thing without worrying about conversion. 
function replace_interface_with_t(arg_types::Type{T}, t) where {T<:Tuple}
    return replace_interface_with_t(fieldtypes(arg_types), t)
end

"""
    peel(::Tuple)
returns (first_element, (rest...))
"""
function peel(t::Tuple)
    h = first(t)
    r = tail(t)
    return (h, r)
end
function peel(::Tuple{})
    error("cannot peel an empty tuple")
end


@testitem "replacing Tuple{Datatypes...}" begin
    struct HasEltype{T} <: DuckDispatch.DuckType end
    input = Tuple{DuckDispatch.This,Any,DuckDispatch.This,Int}
    output = DuckDispatch.replace_interface_with_t(input, HasEltype{Int})
    @test output == (HasEltype{Int},Any,HasEltype{Int},Int)
end
