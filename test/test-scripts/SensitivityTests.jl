filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

setNumberOfParallelSims(12)

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

cell_type = "default"
force_recompile = false

dv_max_time = DiscreteVariation(["overall", "max_time"], 12.0)
dv_save_full_data_interval = DiscreteVariation(configPath("full_data"), 6.0)
dv_save_svg_data_interval = DiscreteVariation(configPath("svg_save"), 6.0)
discrete_variations = [dv_max_time, dv_save_full_data_interval, dv_save_svg_data_interval]

add_variations_result = PhysiCellModelManager.addVariations(GridVariation(), inputs, discrete_variations)
reference_variation_id = add_variations_result.all_variation_ids[1]

xml_path = PhysiCellModelManager.cyclePath(cell_type, "phase_durations", "duration:index:0")
lower_bound = 250.0 - 50.0
upper_bound = 350.0 + 50.0
dv1 = UniformDistributedVariation(xml_path, lower_bound, upper_bound)

xml_path = PhysiCellModelManager.cyclePath(cell_type, "phase_durations", "duration:index:1")
vals = [100.0, 200.0, 300.0]
dv2 = DiscreteVariation(xml_path, vals)

xml_path = PhysiCellModelManager.cyclePath(cell_type, "phase_durations", "duration:index:2")
mu = 300.0
sigma = 50.0
lb = 10.0
ub = 1000.0
dv3 = NormalDistributedVariation(xml_path, mu, sigma; lb=lb, ub=ub)

avs = [CoVariation(dv1, dv3), dv2]

n_points = 2^1-1

gs_fn(simulation_id::Int) = finalPopulationCount(simulation_id)[cell_type]

moat_sampling = run(MOAT(n_points), inputs, avs; force_recompile=force_recompile, reference_variation_id=reference_variation_id, functions=[gs_fn], n_replicates=1)
moat_sampling = run(MOAT(), inputs, avs; force_recompile=force_recompile, reference_variation_id=reference_variation_id, functions=[gs_fn])
moat_sampling = run(MOAT(4; orthogonalize=true), inputs, avs; force_recompile=force_recompile, reference_variation_id=reference_variation_id, functions=[gs_fn])
sobol_sampling = run(Sobolʼ(n_points), inputs, avs; force_recompile=force_recompile, reference_variation_id=reference_variation_id, functions=[gs_fn])
rbd_sampling = run(RBD(n_points), inputs, avs; force_recompile=force_recompile, reference_variation_id=reference_variation_id, functions=[gs_fn])

PhysiCellModelManager.calculateGSA!(moat_sampling, gs_fn)
PhysiCellModelManager.calculateGSA!(sobol_sampling, gs_fn)
PhysiCellModelManager.calculateGSA!(rbd_sampling, gs_fn)

# test sensitivity with config, rules, ic_cells, and ic_ecm at once
config_folder = "template-ecm"
rulesets_collection_folder = "0_template"
custom_code_folder = "template-ecm"
ic_cell_folder = "1_xml"
ic_ecm_folder = "1_xml"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_cell=ic_cell_folder, ic_ecm=ic_ecm_folder)

dv_max_time = DiscreteVariation(["overall", "max_time"], 12.0)
dv_save_full_data_interval = DiscreteVariation(configPath("full_data"), 6.0)
dv_save_svg_data_interval = DiscreteVariation(configPath("svg_save"), 6.0)
discrete_variations = [dv_max_time, dv_save_full_data_interval, dv_save_svg_data_interval]

add_variations_result = PhysiCellModelManager.addVariations(GridVariation(), inputs, discrete_variations)
reference_variation_id = add_variations_result.all_variation_ids[1]

xml_path = PhysiCellModelManager.cyclePath(cell_type, "phase_durations", "duration:index:0")
lower_bound = 250.0 - 50.0
upper_bound = 350.0 + 50.0
dv1 = UniformDistributedVariation(xml_path, lower_bound, upper_bound)

xml_path = rulePath("default", "cycle entry", "decreasing_signals", "max_response")
dv2 = UniformDistributedVariation(xml_path, 0.0, 1.0e-8)

xml_path = icCellsPath("default", "annulus", 1, "inner_radius")
dv3 = UniformDistributedVariation(xml_path, 0.0, 1.0)

xml_path = icECMPath(2, "ellipse", 1, "density")
dv4 = UniformDistributedVariation(xml_path, 0.25, 0.75)

av = CoVariation(dv1, dv2, dv3, dv4)

moat_sampling = run(MOAT(n_points), inputs, av; force_recompile=force_recompile, reference_variation_id=reference_variation_id, functions=[gs_fn])
n_simulations_expected = n_points * (1 + 1) * n_replicates
@test length(moat_sampling.sampling) == n_simulations_expected

sobol_index_methods = (first_order=:Sobol1993, total_order=:Homma1996)
sobol_sampling = run(SobolPCMM(n_points; sobol_index_methods=sobol_index_methods), inputs, av; force_recompile=force_recompile, reference_variation_id=reference_variation_id, functions=[gs_fn])
sobol_index_methods = (first_order=:Saltelli2010, total_order=:Sobol2007)
sobol_sampling = run(SobolPCMM(n_points; sobol_index_methods=sobol_index_methods), inputs, av; force_recompile=force_recompile, reference_variation_id=reference_variation_id, functions=[gs_fn])

reference = simulationIDs(sobol_sampling)[1] |> Simulation
sobol_sampling = run(SobolPCMM(2), reference, av)

# Testing sensitivity with CoVariations
dv_max_time = DiscreteVariation(["overall", "max_time"], 12.0)

reference = createTrial(inputs, dv_max_time; n_replicates=0)

dv_apop = UniformDistributedVariation(configPath("default", "apoptosis", "death_rate"), 0.0, 1.0)
dv_cycle = UniformDistributedVariation(PhysiCellModelManager.cyclePath("default", "phase_durations", "duration:index:0"), 1000.0, 2000.0; flip=true)
dv_necr = NormalDistributedVariation(configPath("default", "necrosis", "death_rate"), 1e-4, 1e-5; lb=0.0, ub=1.0, flip=false)
dv_pressure_hfm = UniformDistributedVariation(rulePath("default", "cycle entry", "decreasing_signals", "signal:name:pressure", "half_max"), 0.1, 0.25)
dv_x0 = UniformDistributedVariation(icCellsPath("default", "disc", 1, "x0"), -100.0, 0.0; flip=true)
dv_anisotropy = UniformDistributedVariation(icECMPath(2, "elliptical_disc", 1, "anisotropy"), 0.0, 1.0)

cv1 = CoVariation([dv_apop, dv_cycle]) #! I think wanted these to only be config variations?
cv2 = CoVariation([dv_necr, dv_pressure_hfm, dv_x0, dv_anisotropy]) #! I think I wanted these to be all different locations?
avs = [cv1, cv2]

method = MOAT(4)
gsa_sampling = run(method, reference, avs)
@test size(gsa_sampling.monad_ids_df) == (4, 3)

method = Sobolʼ(5)
gsa_sampling = run(method, reference, avs)
@test size(gsa_sampling.monad_ids_df) == (5, 4)

method = RBD(5)
gsa_sampling = run(method, reference, avs...) # test the method with Vararg variations
@test size(gsa_sampling.monad_ids_df) == (5, 2)

# print tests
println(stdout, moat_sampling)
println(stdout, sobol_sampling)
println(stdout, rbd_sampling)

