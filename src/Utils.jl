"""
    `tuple_collect(::Type{Union{Types...}}) -> Tuple(Types...)`
Returns a tuple of the types in a Union type.
"""
@generated function tuple_collect(::Type{U}) where {U}
    U === Union{} && return ()
    types = tuple(Base.uniontypes(U)...)
    return :($tuple($(types...)))
end

function make_f_calls(f, tuples)
    first_tuple_types = static_fieldtypes(tuples[1])
    tuple_lengths = length(first_tuple_types)
    number_of_tuples = length(tuples)
    @assert all(length(static_fieldtypes(t)) == tuple_lengths for t in tuples) "all tuples must be same length"
    f_calls = [:(f($(
                   (:(tuples[$j][$i]) for j in 1:number_of_tuples)...)
               )
               )
               for i in 1:tuple_lengths]
    return f_calls
end

@generated function tuple_map(f, tuples...)
    f_calls = make_f_calls(f, tuples)
    quote
        tuple(
            $(f_calls...)
        )
    end
end

@generated function tuple_all(f, tuples...)
    f_calls = make_f_calls(f, tuples)
    with_returns = [:($f_call || return false) for f_call in f_calls]
    quote
        $(with_returns...)
        return true
    end
end