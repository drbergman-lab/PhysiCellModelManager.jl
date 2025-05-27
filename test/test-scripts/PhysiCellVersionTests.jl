filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

@test pcvct.physicellVersion() == readchomp(joinpath(pcvct.physicellDir(), "VERSION.txt"))
@test pcvct.physicellVersion(Simulation(1)) == readchomp(joinpath(pcvct.physicellDir(), "VERSION.txt"))

path_to_file = joinpath("PhysiCell", "Makefile")

lines = readlines(path_to_file)
lines[1] *= " "
open(path_to_file, "w") do f
    for line in lines
        println(f, line)
    end
end

@test !pcvct.gitDirectoryIsClean(pcvct.physicellDir())
initializeModelManager(pcvct.physicellDir(), pcvct.dataDir())
pcvct.physicellVersion()

lines[1] = lines[1][1:end-1]
open(path_to_file, "w") do f
    for line in lines
        println(f, line)
    end
end

@test pcvct.gitDirectoryIsClean(pcvct.physicellDir())

# test with PhysiCell download
original_project_dir = dirname(pcvct.dataDir())

project_dir = "./test-project-download"
createProject(project_dir; clone_physicell=false)
data_dir = joinpath(project_dir, "data")
physicell_dir = joinpath(project_dir, "PhysiCell")
initializeModelManager(physicell_dir, data_dir)
pcvct.resolvePhysiCellVersionID()

initializeModelManager(original_project_dir)
pcvct.resolvePhysiCellVersionID()