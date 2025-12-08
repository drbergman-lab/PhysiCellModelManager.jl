filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

PhysiCellModelManager.constituentIDs(Trial, 1)
sim_ids = simulationIDs()[1:2]
simulationIDs(Simulation.(sim_ids))
PhysiCellModelManager.trialMonads(1)
monadIDs()
monadIDs(Trial(1))

@test_warn "`getSimulationIDs` is deprecated. Use `simulationIDs` instead." getSimulationIDs(Trial(1))
@test_warn "`getMonadIDs` is deprecated. Use `monadIDs` instead." getMonadIDs(Trial(1))

path_to_inputs      = joinpath(PhysiCellModelManager.dataDir(), "inputs", "inputs.toml")
path_to_fake_inputs = joinpath(PhysiCellModelManager.dataDir(), "inputs", "not_inputs.toml")

mv(path_to_inputs, path_to_fake_inputs)

@test initializeModelManager() == false

mv(path_to_fake_inputs, path_to_inputs)

@test initializeModelManager() == true
