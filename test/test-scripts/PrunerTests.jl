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

simulation = createTrial(inputs, discrete_variations; use_previous=false)
@test simulation isa Simulation

prune_options = PruneOptions(true, true, true, true, true, true)
out = run(simulation; force_recompile=false, prune_options=prune_options)
@test out.n_success == 1

pruned_simulation_id = simulation.id #! save this for use in other tests