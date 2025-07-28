filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

snapshot = PhysiCellSnapshot(1, :final)
c = connectedComponents(snapshot)
c = connectedComponents(snapshot; include_cell_type_names=:all)
cell_types = PhysiCellModelManager.cellTypeToNameDict(snapshot) |> values |> collect
c = connectedComponents(snapshot; include_cell_type_names=[cell_types])
c = connectedComponents(snapshot, "neighbors"; include_cell_type_names=[cell_types], exclude_cell_type_names=cell_types) #! for it to have empty keys after excluding

simulation_id = simulation_from_import |> simulationIDs |> first
snapshot = PhysiCellModelManager.PhysiCellSnapshot(simulation_id, :final)
c = connectedComponents(snapshot; include_cell_type_names=["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"])
c = connectedComponents(snapshot; include_dead=true)
c = connectedComponents(snapshot; include_cell_type_names=["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"], include_dead=true)

#! deprecation tests
@test_warn "Keyword argument `include_cell_types` is deprecated. Use `include_cell_type_names` instead." connectedComponents(snapshot; include_cell_types=:all)
@test_warn "Keyword argument `exclude_cell_types` is deprecated. Use `exclude_cell_type_names` instead." connectedComponents(snapshot; exclude_cell_types=cell_types)