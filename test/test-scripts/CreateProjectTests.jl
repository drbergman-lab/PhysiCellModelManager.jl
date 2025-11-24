using Downloads, LightXML

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

project_dir = "pcmm_project_sans_template"
createProject(project_dir; template_as_default=false)
@test PhysiCellModelManager.isInitialized()
@test PhysiCellModelManager.dataDir() == normpath(abspath(joinpath(project_dir, "data")))
@test PhysiCellModelManager.physicellDir() == normpath(abspath(joinpath(project_dir, "PhysiCell")))

project_dir = "."
createProject(project_dir)
@test PhysiCellModelManager.isInitialized()
@test PhysiCellModelManager.dataDir() == normpath(abspath(joinpath(project_dir, "data")))
@test PhysiCellModelManager.physicellDir() == normpath(abspath(joinpath(project_dir, "PhysiCell")))

# tests for coverage
@test PhysiCellModelManager.icFilename("ecms") == "ecm.csv"
@test PhysiCellModelManager.icFilename("dcs") == "dcs.csv"

# test request without authentication token
PCMM_PUBLIC_REPO_AUTH = ENV["PCMM_PUBLIC_REPO_AUTH"]
delete!(ENV, "PCMM_PUBLIC_REPO_AUTH")

try
    PhysiCellModelManager.latestReleaseTag("https://github.com/drbergman/PhysiCell")
catch e
    @test e isa RequestError
else
    @test true
end

ENV["PCMM_PUBLIC_REPO_AUTH"] = PCMM_PUBLIC_REPO_AUTH

# run the generated script
include("../scripts/GenerateData.jl") #! this file is created by CreateProjectTests.jl