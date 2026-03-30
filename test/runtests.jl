using PhysiCellModelManager, Test

include("./test-scripts/PrintHelpers.jl")

# Clean up artifacts from previous test runs so each run starts fresh.
# Artifacts are left in place after the run for manual inspection.
let test_dir = @__DIR__
    for artifact in ["data", "PhysiCell", "scripts", "IntracellularTestExport",
                     "InvalidRulesetExport", "test-project-download",
                     "pcmm_project_sans_template", "test.out"]
        path = joinpath(test_dir, artifact)
        if ispath(path)
            rm(path; recursive=true, force=true)
        end
    end
end

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
    "CalibrationTests.jl",
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