using Plots

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulation = Simulation(1)
out = run(simulation)
finalPopulationCount(out)

plot(Simulation(1))
plot(Sampling(1))

plotbycelltype(Simulation(1))
plotbycelltype(Sampling(1))
plotbycelltype(Sampling(1); include_cell_type_names="default")

# misc tests
out = Monad(1; n_replicates=3) |> run
mpts = PhysiCellModelManager.MonadPopulationTimeSeries(1)
plot(out)
plot(out.trial)
plot(out; include_cell_type_names="default")
plotbycelltype(out)
plotbycelltype(out.trial)

all_cell_types = ["cancer", "immune", "epi", "mes"]
PhysiCellModelManager.processIncludeCellTypes(["cancer", "immune"], all_cell_types)
PhysiCellModelManager.processIncludeCellTypes(["epi", "mes", ["epi", "mes"]], all_cell_types)
@test_throws ArgumentError PhysiCellModelManager.processIncludeCellTypes(:mes, all_cell_types)
@test_throws ArgumentError PhysiCellModelManager.processIncludeCellTypes(1, all_cell_types)

PhysiCellModelManager.processExcludeCellTypes("cancer")
@test_throws ArgumentError PhysiCellModelManager.processExcludeCellTypes(:mes)
plot(out; include_cell_type_names="default", exclude_cell_type_names="default")

plot(simulation_from_import; include_cell_type_names=[["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"]])
monad = Monad(simulation_from_import; n_replicates=2)
out = run(monad)
plot(out; include_cell_type_names=[["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"]])

@test_throws ArgumentError plot(run(Trial(1)))

plotbycelltype(simulation_from_import; include_cell_type_names="fast T cell", exclude_cell_type_names="fast T cell")

@test ismissing(PhysiCellSnapshot(pruned_simulation_id, :initial))
@test ismissing(finalPopulationCount(pruned_simulation_id))

spts = PhysiCellModelManager.SimulationPopulationTimeSeries(1)
Base.show(stdout, MIME"text/plain"(), spts)
Base.show(stdout, MIME"text/plain"(), mpts)

@test PhysiCellModelManager.formatTimeRange([78.0]) == "78.0"
@test PhysiCellModelManager.formatTimeRange([0.0, 40.0, 78.0]) == "0.0-78.0 (not equally spaced)"

#! deprecation tests
@test_warn "`include_cell_types` is deprecated as a keyword. Use `include_cell_type_names` instead." plot(out; include_cell_types="fast T cell")
@test_warn "`exclude_cell_types` is deprecated as a keyword. Use `exclude_cell_type_names` instead." plot(out; exclude_cell_types="fast T cell")

@test_warn "`include_cell_types` is deprecated as a keyword. Use `include_cell_type_names` instead." plotbycelltype(out; include_cell_types="fast T cell")
@test_warn "`exclude_cell_types` is deprecated as a keyword. Use `exclude_cell_type_names` instead." plotbycelltype(out; exclude_cell_types="fast T cell")