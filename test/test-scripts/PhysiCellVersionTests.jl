filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

@test PhysiCellModelManager.physicellVersion() == readchomp(joinpath(PhysiCellModelManager.physicellDir(), "VERSION.txt"))

sim_id = simulationIDs()[1]
@test PhysiCellModelManager.physicellVersion(Simulation(sim_id)) == readchomp(joinpath(PhysiCellModelManager.physicellDir(), "VERSION.txt"))

path_to_file = joinpath("PhysiCell", "Makefile")

lines = readlines(path_to_file)
lines[1] *= " "
open(path_to_file, "w") do f
    for line in lines
        println(f, line)
    end
end

println("Testing that PCMM recognizes PhysiCell is dirty...")
@test !PhysiCellModelManager.gitDirectoryIsClean(PhysiCellModelManager.physicellDir())
println("PhysiCell should still be dirty on initialization...")
@test initializeModelManager(PhysiCellModelManager.physicellDir(), PhysiCellModelManager.dataDir())
PhysiCellModelManager.physicellVersion()

lines[1] = lines[1][1:end-1]
open(path_to_file, "w") do f
    for line in lines
        println(f, line)
    end
end

@test PhysiCellModelManager.gitDirectoryIsClean(PhysiCellModelManager.physicellDir())

# test with PhysiCell download
original_project_dir = dirname(PhysiCellModelManager.dataDir())

project_dir = "./test-project-download"
createProject(project_dir; clone_physicell=false)
data_dir = joinpath(project_dir, "data")
physicell_dir = joinpath(project_dir, "PhysiCell")
@test PhysiCellModelManager.isInitialized()
@test PhysiCellModelManager.dataDir() == normpath(abspath(data_dir))
@test PhysiCellModelManager.physicellDir() == normpath(abspath(physicell_dir))
@test initializeModelManager(physicell_dir, data_dir)
PhysiCellModelManager.resolvePhysiCellVersionID()

@test initializeModelManager(original_project_dir)
PhysiCellModelManager.resolvePhysiCellVersionID()
