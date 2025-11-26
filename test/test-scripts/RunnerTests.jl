filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

n_sims = length(Monad(1))
monad = Monad(1; n_replicates=1, use_previous=false)
run(monad)
@test length(monad) == n_sims + 1 #! how many simulations were attached to this monad when run
@test length(simulationIDs(monad)) == n_sims+1 #! how many simulations are stored in simulations.csv

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

n_replicates = 1

discrete_variations = []
push!(discrete_variations, DiscreteVariation(configPath("max_time"), 12.0))
push!(discrete_variations, DiscreteVariation(configPath("full_data"), 6.0))
push!(discrete_variations, DiscreteVariation(configPath("svg_save"), 6.0))

simulation = createTrial(inputs, discrete_variations)

out = run(simulation)
@test out.trial isa Simulation
@test out.n_scheduled == 1
@test out.n_success == 1

out2 = run(inputs, discrete_variations)
@test out2.trial isa Simulation
@test out2.n_scheduled == 0
@test out2.n_success == 0

@test PhysiCellModelManager.trialID(out) == PhysiCellModelManager.trialID(out2)
@test out.trial.inputs == out2.trial.inputs
@test out.trial.variation_id == out2.trial.variation_id

query = PhysiCellModelManager.constructSelectQuery("simulations", "WHERE simulation_id=1")
df = PhysiCellModelManager.queryToDataFrame(query; is_row=true)

cell_type = "default"
discrete_variations = []
xml_path = configPath(cell_type, "cycle_duration", 0)
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
xml_path = configPath(cell_type, "cycle_duration", 1)
push!(discrete_variations, DiscreteVariation(xml_path, 3.0))
xml_path = configPath(cell_type, "cycle_duration", 2)
push!(discrete_variations, DiscreteVariation(xml_path, 4.0))
xml_path = configPath(cell_type, "cycle_duration", 3)
push!(discrete_variations, DiscreteVariation(xml_path, 5.0))

sampling = createTrial(simulation, discrete_variations; n_replicates=n_replicates)

out = run(sampling; force_recompile=false)
@test out.n_success == length(sampling)

out2 = run(simulation, discrete_variations; n_replicates=n_replicates, force_recompile=false)
@test out2.trial isa Sampling
@test PhysiCellModelManager.trialID(out2) == sampling.id
@test out2.trial.inputs == sampling.inputs
@test Set(PhysiCellModelManager.readConstituentIDs(out2.trial)) == Set(PhysiCellModelManager.readConstituentIDs(sampling))
@test Set(PhysiCellModelManager.simulationIDs(out2.trial)) == Set(PhysiCellModelManager.simulationIDs(sampling))
@test out2.n_scheduled == 0
@test out2.n_success == 0

n_simulations = length(sampling) #! number of simulations recorded (in .csvs) for this sampling
n_expected_sims = n_replicates * (discrete_variations .|> length |> prod)
n_variations = length(sampling.monads)

# make sure the number of simulations in this sampling is what we expected based on...
@test n_simulations == n_expected_sims #! the discrete_variations...
@test n_simulations == n_variations * n_replicates #! ...how many variation ids we recorded (number of rulesets_variations_ids must match variation_ids on construction of sampling)
@test n_simulations == out.n_success #! ...how many simulations succeeded

out = run(sampling; force_recompile=false)

# no new simulations should have been run
@test out.n_success == 0

trial = Trial([sampling])
@test trial isa Trial

out = run(trial; force_recompile=false)

# no new simulations should have been run
@test out.n_success == 0

@test_warn "`runAbstractTrial` is deprecated. Use `run` instead." runAbstractTrial(trial; force_recompile=false)

# run a sim that will produce an error
dv = DiscreteVariation(rulePath("default", "cycle entry", "decreasing_signals", "max_response"), 100.0)
out = run(inputs, dv)
@test out.n_success == 0

println(stdout, out)