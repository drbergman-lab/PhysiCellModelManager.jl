using Plots, PairCorrelationFunction

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulation_id = 1
simulation = Simulation(simulation_id)
out = run(simulation)
snapshot = PhysiCellSnapshot(simulation_id, :initial)
cell_types = PhysiCellModelManager.cellTypeToNameDict(simulation) |> values |> collect
result = pcf(simulation, cell_types[1])

plot(result)
plot(result; time_unit=:s, distance_unit=:mm)
plot(result; time_unit=:s, distance_unit=:cm)

Base.show(stdout, MIME"text/plain"(), result)

result = PhysiCellModelManager.pcf(PhysiCellSnapshot(simulation_id, :initial), cell_types[1])
result = PhysiCellModelManager.pcf(simulation_id, :initial, cell_types[1])
result = PhysiCellModelManager.pcf(out, :initial, [cell_types[1]], cell_types[1])

plot(result; time_unit=:s)
plot([result]; time_unit=:h)
plot([result]; time_unit=:d)
plot([result]; time_unit=:w)
plot([result]; time_unit=:mo)
plot([result]; time_unit=:y)

Base.show(stdout, MIME"text/plain"(), result)

@test_throws ArgumentError PhysiCellModelManager.pcf(simulation, :initial, :default) #! third argument should be a string or vector of strings
@test_throws ArgumentError plot([result]; time_unit=:not_a_unit)
@test_throws ArgumentError plot([result]; distance_unit=:not_a_unit)

#! test 3d
dvs = DiscreteVariation[]
domain = (z_min=-20.0, z_max=20.0)
addDomainVariationDimension!(dvs, domain)
push!(dvs, DiscreteVariation(["domain", "use_2D"], false))
out = run(simulation, dvs)
simulation_id = out.trial |> simulationIDs |> first
result = PhysiCellModelManager.pcf(simulation_id, :final, cell_types[1])

simulation_id = simulation_from_import |> simulationIDs |> first
snapshot = PhysiCellSnapshot(simulation_id, :final)
cell_types = PhysiCellModelManager.cellTypeToNameDict(snapshot) |> values |> collect
result = PhysiCellModelManager.pcf(snapshot, cell_types[1], cell_types[2])
@test_throws ArgumentError PhysiCellModelManager.pcf(snapshot, cell_types[1], cell_types[1:2])