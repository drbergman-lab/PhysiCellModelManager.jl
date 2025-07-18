filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

discrete_variations = []
push!(discrete_variations, DiscreteVariation(configPath("max_time"), 12.0))
push!(discrete_variations, DiscreteVariation(configPath("full_data"), 6.0))
push!(discrete_variations, DiscreteVariation(configPath("svg_save"), 6.0))

out = run(inputs, discrete_variations; use_previous=false)
@test out.trial isa Simulation
cell_labels = pcvct.cellLabels(out.trial)
substrate_names = pcvct.substrateNames(out.trial)
sequence = PhysiCellSequence(pcvct.trialID(out); include_cells=true, include_substrates=true)

seq_dict = cellDataSequence(sequence, "elapsed_time_in_phase"; include_dead=true)
@test length(seq_dict) == length(seq_dict.dict)
@test seq_dict[pcvct.AgentID(0)] == seq_dict[0]
@test haskey(seq_dict, pcvct.AgentID(0))
@test haskey(seq_dict, 0)
@test_nowarn setindex!(seq_dict, seq_dict[0], pcvct.AgentID(78787878))
@test_nowarn delete!(seq_dict, pcvct.AgentID(78787878))
@test_nowarn setindex!(seq_dict, seq_dict[0], 78787878)
@test_nowarn delete!(seq_dict, 78787878)
@test_warn "`getCellDataSequence` is deprecated. Use `cellDataSequence` instead." getCellDataSequence(sequence, "elapsed_time_in_phase"; include_dead=true)

simulation_population_time_series = pcvct.populationTimeSeries(out.trial; include_dead=true)
simulation_population_time_series["time"]
cell_types = keys(simulation_population_time_series.cell_count)
simulation_population_time_series[first(cell_types)]
@test_throws ArgumentError simulation_population_time_series["not_a_cell_type"]
simulation_population_time_series = pcvct.populationTimeSeries(out.trial; include_dead=false)

# brief pause for motility testing
for direction in [:x, :y, :z, :any]
    local mean_speed_dicts = motilityStatistics(Simulation(pcvct.trialID(out)); direction=direction)
end
@test ismissing(motilityStatistics(pruned_simulation_id))

@test ismissing(PhysiCellSequence(pruned_simulation_id))
pruned_simulation = Simulation(pruned_simulation_id)
@test pcvct.pathToOutputXML(pruned_simulation) |> pcvct.cellLabels |> isempty
@test pcvct.pathToOutputXML(pruned_simulation) |> pcvct.substrateNames |> isempty

monad = createTrial(out.trial; n_replicates=0)
@test monad isa Monad

monad = createTrial(monad; n_replicates=2)
out = run(monad)
monad = out.trial
monad_population_time_series = pcvct.populationTimeSeries(monad; include_dead=false)
monad_population_time_series["time"]
@test_throws ArgumentError monad_population_time_series["not_a_cell_type"]

# misc testing
snapshot = sequence.snapshots[1]
pcvct.cellLabels(snapshot)
pcvct.substrateNames(snapshot)
pcvct.loadSubstrates!(sequence)
pcvct.loadMesh!(sequence)
snapshot = PhysiCellSnapshot(1, 0)
sequence = PhysiCellSequence(Simulation(1))
cellDataSequence(1, "position")
cellDataSequence(Simulation(1), "position")

simulation = Simulation(monad)
out = run(simulation; prune_options=PruneOptions(prune_mat=true))
@test out.n_success == 1 #! confirm that creating a simulation using simulation = Simulation(monad) creates a new simulation (not one already in the db)
mat_pruned_simulation_id = pcvct.trialID(out)
PhysiCellSnapshot(mat_pruned_simulation_id, 0; include_cells=true)
PhysiCellSnapshot(mat_pruned_simulation_id, 0; include_substrates=true)
snapshot = PhysiCellSnapshot(mat_pruned_simulation_id, 0)
@test ismissing(pcvct.averageExtracellularSubstrate(snapshot))

sequence = PhysiCellSequence(mat_pruned_simulation_id; include_attachments=true, include_spring_attachments=true, include_neighbors=true)
pcvct.loadGraph!(sequence, :attachments)
pcvct.loadGraph!(sequence, "spring_attachments")
pcvct.loadGraph!(sequence, :neighbors)

Base.show(stdout, MIME"text/plain"(), snapshot)
Base.show(stdout, MIME"text/plain"(), sequence)
Base.show(stdout, MIME"text/plain"(), sequence.snapshots[1])

simulation = Simulation(monad)
out = run(simulation; prune_options=PruneOptions(prune_txt=true))
txt_pruned_simulation_id = pcvct.trialID(out)
@test ismissing(PhysiCellSnapshot(txt_pruned_simulation_id, 0; include_attachments=true))
@test ismissing(PhysiCellSnapshot(txt_pruned_simulation_id, 0; include_spring_attachments=true))
@test ismissing(PhysiCellSnapshot(txt_pruned_simulation_id, 0; include_neighbors=true))