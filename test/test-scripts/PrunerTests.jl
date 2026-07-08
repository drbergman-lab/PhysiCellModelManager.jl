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

#! postSimulationCleanup runs AFTER the user post_processor, so the callback must
#! see the intact (un-pruned) output folder; pruning only happens once it returns.
outputMatFiles(path) = filter(f -> startswith(f, "output") && endswith(f, ".mat"), readdir(path))

intact_during_callback = Ref(false)
callback_output_path = Ref("")
cb_simulation = createTrial(inputs, discrete_variations; use_previous=false)
out_cb = run(cb_simulation; force_recompile=false, prune_options=prune_options,
    post_processor = function (sp)
        path = pathToOutputFolder(sp)
        callback_output_path[] = path
        intact_during_callback[] = !isempty(outputMatFiles(path)) #! output present before cleanup
        return nothing
    end)
@test out_cb.n_success == 1
@test intact_during_callback[]                          #! callback saw un-pruned output
@test isempty(outputMatFiles(callback_output_path[]))   #! cleanup pruned it afterward