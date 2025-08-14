filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

PhysiCellModelManager.readConstituentIDs(Trial, 1)
simulationIDs([Simulation(1), Simulation(2)])
PhysiCellModelManager.trialMonads(1)
getMonadIDs()
getMonadIDs(Trial(1))

@test_warn "`getSimulationIDs` is deprecated. Use `simulationIDs` instead." getSimulationIDs(Trial(1))

path_to_inputs      = joinpath(PhysiCellModelManager.dataDir(), "inputs", "inputs.toml")
path_to_fake_inputs = joinpath(PhysiCellModelManager.dataDir(), "inputs", "not_inputs.toml")

mv(path_to_inputs, path_to_fake_inputs)

@test initializeModelManager() == false

mv(path_to_fake_inputs, path_to_inputs)

@test initializeModelManager() == true
