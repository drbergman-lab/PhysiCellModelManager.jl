using pcvct, Test

include("./test-scripts/PrintHelpers.jl")

@testset "pcvct.jl" begin

    include("./test-scripts/CreateProjectTests.jl")

    include("./scripts/GenerateData.jl") #! this file is created by CreateProjectTests.jl

    include("./test-scripts/ProjectConfigurationTests.jl")

    include("./test-scripts/RunnerTests.jl")
    include("./test-scripts/UserAPITests.jl")
    include("./test-scripts/ImportTests.jl")
    include("./test-scripts/PrunerTests.jl")
    include("./test-scripts/ConfigurationTests.jl")

    include("./test-scripts/IntracellularTests.jl")
    include("./test-scripts/ICCellTests.jl")
    include("./test-scripts/ICECMTests.jl")

    include("./test-scripts/ExportTests.jl")
    include("./test-scripts/SensitivityTests.jl")
    include("./test-scripts/DatabaseTests.jl")
    include("./test-scripts/ClassesTests.jl")

    #! post-processing tests
    include("./test-scripts/LoaderTests.jl")
    include("./test-scripts/MovieTests.jl")
    include("./test-scripts/PopulationTests.jl")
    include("./test-scripts/SubstrateTests.jl")
    include("./test-scripts/GraphsTests.jl")
    include("./test-scripts/PCFTests.jl")

    include("./test-scripts/VariationsTests.jl")
    include("./test-scripts/HPCTests.jl")
    include("./test-scripts/ModuleTests.jl")
    include("./test-scripts/PhysiCellVersionTests.jl")
    include("./test-scripts/PhysiCellStudioTests.jl")

    #! probably want this one last (it deletes/resets things)
    include("./test-scripts/DeletionTests.jl")

    #! test deps
    include("./test-scripts/DepsTests.jl")
end