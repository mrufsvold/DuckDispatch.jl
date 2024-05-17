using DuckDispatch
using TestItemRunner: @run_package_tests
using Test
using Aqua
using JET

@run_package_tests

@testset "DuckDispatch.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(DuckDispatch)
    end
    # @testset "Code linting (JET.jl)" begin
    #     JET.test_package(DuckDispatch; target_defined_modules = true)
    # end
    
end
