using InterfaceDispatch
using TestItemRunner: @run_package_tests
using Test
using Aqua
using JET

@run_package_tests

@testset "InterfaceDispatch.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(InterfaceDispatch; ambiguities = false,)
    end
    # @testset "Code linting (JET.jl)" begin
    #     JET.test_package(InterfaceDispatch; target_defined_modules = true)
    # end
    
end
