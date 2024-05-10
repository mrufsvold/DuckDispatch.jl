using InterfaceDispatch
using Test
using Aqua
using JET

@testset "InterfaceDispatch.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(InterfaceDispatch; ambiguities = false,)
    end
    @testset "Code linting (JET.jl)" begin
        JET.test_package(InterfaceDispatch; target_defined_modules = true)
    end
    # Write your tests here.
end
