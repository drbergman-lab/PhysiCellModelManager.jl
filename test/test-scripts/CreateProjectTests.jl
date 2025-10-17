using PhysiCellModelManager.PCMMXML, XML

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

include("../scripts/GenerateData.jl") #! this file is created by CreateProjectTests.jl