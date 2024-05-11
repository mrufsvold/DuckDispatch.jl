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
    arg_tail, H = popfirst!!(arg_types)
    # replace This
    head_type = H <: This ? T : H

    # recurse
    tail_types = replace_interface_with_t(arg_tail, T)

    return pushfirst!!(tail_types, head_type)
end
# turns tuple type into a tuple of types and back again so that the recursive function above
# can do its thing without worrying about conversion. 
function replace_interface_with_t(arg_types::Type{T}, t) where {T<:Tuple}
    return replace_interface_with_t(fieldtypes(arg_types), t)
end

@testitem "replacing Tuple{Datatypes...}" begin
    struct HasEltype{T} <: InterfaceDispatch.InterfaceKind end
    input = Tuple{InterfaceDispatch.This,Any,InterfaceDispatch.This,Int}
    output = InterfaceDispatch.replace_interface_with_t(input, HasEltype{Int})
    @test output == (HasEltype{Int},Any,HasEltype{Int},Int)
end