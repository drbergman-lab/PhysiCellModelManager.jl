using LightXML

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

project_dir = "."
createProject(project_dir)

# tests for coverage
@test pcvct.icFilename("ecms") == "ecm.csv"
@test pcvct.icFilename("dcs") == "dcs.csv"

include("../scripts/GenerateData.jl") #! this file is created by CreateProjectTests.jl