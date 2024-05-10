module InterfaceDispatch

public 
    @interface,
    @with_interface,
    Interface,
    InterfaceKind,
    GenericWrap,
    This,
    narrow,
    Meet,
    wrap,
    unwrap,
    rewrap


@static if false
    macro test end
    macro test_throws end
end

using BangBang: popfirst!!, pushfirst!!, append!!, push!!
using TestItems: @testitem
using SumTypes: @sum_type, @cases
using ExproniconLite: JLFunction, JLStruct, is_function, xcall, codegen_ast

include("TypeUtils.jl")
include("MetaUtils.jl")
include("Interfaces.jl")
include("InterfaceMacro.jl")
include("DispatchMacro.jl")

end
