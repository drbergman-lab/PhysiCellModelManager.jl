filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

method = GridVariation()

dv = DiscreteVariation(configPath("max_time"), [12.0, 13.0])

out = run(method, inputs, dv)

method = LHSVariation(3)
dv = UniformDistributedVariation(configPath("max_time"), 12.0, 20.0)
reference = simulationIDs(out)[1] |> Simulation
out = run(method, reference, dv)

method = SobolVariation(4)
out = run(method, reference, dv)

method = RBDVariation(5)
out = run(method, reference, dv)

@test_throws ArgumentError createTrial(inputs, 1, 2, 3)
@test_throws ArgumentError createTrial(reference, 1, dv, 3)