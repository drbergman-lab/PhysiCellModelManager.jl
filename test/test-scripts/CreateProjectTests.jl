using LightXML

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

project_dir = "."
createProject(project_dir)

# tests for coverage
@test PhysiCellModelManager.icFilename("ecms") == "ecm.csv"
@test PhysiCellModelManager.icFilename("dcs") == "dcs.csv"

include("../scripts/GenerateData.jl") #! this file is created by CreateProjectTests.jl