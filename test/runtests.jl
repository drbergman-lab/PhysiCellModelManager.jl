using PhysiCellModelManager, Test

include("./test-scripts/PrintHelpers.jl")

test_order = [
    "CreateProjectTests.jl",
    "ProjectConfigurationTests.jl",
    "RunnerTests.jl",
    "UserAPITests.jl",
    "ImportTests.jl",
    "PrunerTests.jl",
    "ConfigurationTests.jl",
    "IntracellularTests.jl",
    "ICCellTests.jl",
    "ICECMTests.jl",
    "ExportTests.jl",
    "SensitivityTests.jl",
    "DatabaseTests.jl",
    "ClassesTests.jl",
    "LoaderTests.jl",
    "MovieTests.jl",
    "PopulationTests.jl",
    "SubstrateTests.jl",
    "GraphsTests.jl",
    "PCFTests.jl",
    "RuntimeTests.jl",
    "VariationsTests.jl",
    "HPCTests.jl",
    "ModuleTests.jl",
    "PhysiCellVersionTests.jl",
    "PhysiCellStudioTests.jl",
    "DeletionTests.jl",
    "DepsTests.jl"
]

@testset "PhysiCellModelManager.jl" begin

    for test_file in test_order
        @testset "$test_file" begin
            include("./test-scripts/$(test_file)")
            @test_nowarn PhysiCellModelManager.databaseDiagnostics()
        end
    end

end