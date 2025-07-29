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
