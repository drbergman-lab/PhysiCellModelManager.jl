filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulation_id = 1
simulation = Simulation(simulation_id)
out = run(simulation)
asts = PhysiCellModelManager.AverageSubstrateTimeSeries(simulation_id)
asts = PhysiCellModelManager.AverageSubstrateTimeSeries(out)
ests = PhysiCellModelManager.ExtracellularSubstrateTimeSeries(simulation_id)
ests = PhysiCellModelManager.ExtracellularSubstrateTimeSeries(out)

@test ismissing(PhysiCellModelManager.AverageSubstrateTimeSeries(pruned_simulation_id))
snapshot = PhysiCellSnapshot(pruned_simulation_id, :initial)
@test ismissing(snapshot)
@test ismissing(PhysiCellModelManager.ExtracellularSubstrateTimeSeries(pruned_simulation_id))

#! misc tests
asts["time"]
substrate_names = keys(asts.substrate_concentrations)
asts[first(substrate_names)]
@test_throws ArgumentError asts["not_a_substrate"]

ests["time"]
cell_types = keys(ests.data)
ests[first(cell_types)]
@test_throws ArgumentError ests["not_a_cell_type"]

println(stdout, asts)
println(stdout, ests)