module DuckDispatch

if VERSION >= v"1.11"
public 
    @interface,
    @with_interface,
    Guise,
    DuckType,
    GenericWrap,
    This,
    narrow,
    Meet,
    wrap,
    unwrap,
    rewrap
end

@static if false
    macro test end
    macro test_throws end
end

using BangBang: append!!, push!!
using Base: tail
using TestItems: @testitem
using SumTypes: @sum_type, @cases
using ExproniconLite: JLFunction, JLStruct, is_function, xcall, codegen_ast

include("TypeUtils.jl")
include("MetaUtils.jl")
include("Guises.jl")
include("GuiseMacro.jl")
include("DispatchMacro.jl")

end
