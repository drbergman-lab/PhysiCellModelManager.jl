using LightXML

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

n_replicates = 2

path_to_xml = joinpath("data", "inputs", "configs", config_folder, "PhysiCell_settings.xml")

cell_type = "default"
substrate = "substrate"

#! build all the possible path elements supported by the configPath function
    #! single token paths
single_tokens = ["x_min", "x_max", "y_min", "y_max", "z_min", "z_max", "dx", "dy", "dz", "use_2D", "max_time", "dt_intracellular", "dt_diffusion", "dt_mechanics", "dt_phenotype", "full_data_interval", "SVG_save_interval"]
element_paths = configPath.(single_tokens)

    #! double token paths
substrate_double_tokens = ["diffusion_coefficient", "decay_rate", "initial_condition", "Dirichlet_boundary_condition", "xmin", "xmax", "ymin", "ymax", "zmin", "zmax"]
append!(element_paths, [configPath(substrate, token) for token in substrate_double_tokens])

cell_type_double_tokens = ["total", "fluid_fraction", "nuclear", "fluid_change_rate", "cytoplasmic_biomass_change_rate", "nuclear_biomass_change_rate", "calcified_fraction", "calcification_rate", "relative_rupture_volume", "cell_cell_adhesion_strength", "cell_cell_repulsion_strength", "relative_maximum_adhesion_distance", "attachment_elastic_constant", "attachment_rate", "detachment_rate", "maximum_number_of_attachments", "set_relative_equilibrium_distance", "set_absolute_equilibrium_distance", "speed", "persistence_time", "migration_bias", "apoptotic_phagocytosis_rate", "necrotic_phagocytosis_rate", "other_dead_phagocytosis_rate", "attack_damage_rate", "attack_duration", "damage_rate", "damage_repair_rate", "custom:sample"]
append!(element_paths, [configPath(cell_type, token) for token in cell_type_double_tokens])

push!(element_paths, configPath("user_parameters", "number_of_cells"))
push!(element_paths, PhysiCellModelManager.userParametersPath("number_of_cells"))

save_double_tokens = ["full", "SVG", "svg"]
append!(element_paths, [configPath("save", token) for token in save_double_tokens])

    #! triple token paths
append!(element_paths, [configPath(substrate, "Dirichlet_options", token) for token in ["xmin", "xmax", "ymin", "ymax", "zmin", "zmax"]])

append!(element_paths, [configPath(cell_type, tag, 0) for tag in ["cycle_rate", "cycle_duration"]])

common_death_tags = ["rate", "unlysed_fluid_change_rate", "lysed_fluid_change_rate", "cytoplasmic_biomass_change_rate", "nuclear_biomass_change_rate", "calcification_rate", "relative_rupture_volume"]
append!(element_paths, [configPath(cell_type, "apoptosis", tag) for tag in common_death_tags])
append!(element_paths, [configPath(cell_type, "necrosis", tag) for tag in common_death_tags])

append!(element_paths, [configPath(cell_type, "apoptosis", tag) for tag in ["duration", "transition_rate"]])
append!(element_paths, [configPath(cell_type, "necrosis", tag) for tag in ["duration_0", "transition_rate_0", "duration_1", "transition_rate_1"]])

push!(element_paths, configPath(cell_type, "adhesion", cell_type))

append!(element_paths, [configPath(cell_type, "motility", tag) for tag in ["enabled", "use_2D"]])
append!(element_paths, [configPath(cell_type, "chemotaxis", tag) for tag in ["enabled", "substrate", "direction"]])
append!(element_paths, [configPath(cell_type, "advanced_chemotaxis", tag) for tag in ["enabled", "normalize_each_gradient", substrate]])

append!(element_paths, [configPath(cell_type, substrate, tag) for tag in ["secretion_rate", "secretion_target", "uptake_rate", "net_export_rate"]])
append!(element_paths, [configPath(cell_type, "phagocytose", tag) for tag in ["apoptotic", "necrotic", "other_dead", cell_type]])

append!(element_paths, [configPath(cell_type, tag, cell_type) for tag in ["fuse to", "attack", "transform to"]])
push!(element_paths, PhysiCellModelManager.attackPath(cell_type, cell_type))
push!(element_paths, PhysiCellModelManager.attackRatesPath(cell_type, cell_type))

push!(element_paths, configPath(cell_type, "custom", "sample"))

    #! four token paths
append!(element_paths, [configPath(cell_type, "cycle", tag, 0) for tag in ["duration", "rate"]])
append!(element_paths, [configPath(cell_type, "necrosis", tag1, tag2) for tag1 in ["duration", "transition_rate"], tag2 in [0, 1]] |> vec)
append!(element_paths, [configPath(cell_type, "initial_parameter_distribution", "Volume", tag) for tag in ["mu", "sigma", "lower_bound", "upper_bound"]])
append!(element_paths, [configPath(cell_type, "initial_parameter_distribution", "apoptosis", tag) for tag in ["min", "max"]])

#! these paths are known not to be in the template xml (but could be in other xmls)
paths_not_in_template = [
    configPath("dt_intracellular"),
    configPath(cell_type, "cycle", "rate", 0),
    configPath(cell_type, "apoptosis", "transition_rate"),
    configPath(cell_type, "necrosis", "transition_rate", 0),
    configPath(cell_type, "necrosis", "transition_rate", 1),
    configPath(cell_type, "initial_parameter_distribution", "Volume", "lower_bound")
]

#! these are paths that have already been accounted for or don't want to try varying (maybe not a number)
paths_to_skip = [
    configPath("max_time"),
    configPath("use_2D"),
    configPath("full_data_interval"),
    configPath("SVG_save_interval"),
    configPath.(["x_min", "x_max", "y_min", "y_max", "z_min", "z_max", "dx", "dy", "dz"])...,
    [configPath(cell_type, "motility", tag) for tag in ["enabled", "use_2D"]]...,
    [configPath(cell_type, "chemotaxis", tag) for tag in ["enabled", "substrate", "direction"]]...,
    [configPath(cell_type, "advanced_chemotaxis", tag) for tag in ["enabled", "normalize_each_gradient"]]...
]

xml_doc = parse_file(path_to_xml)
indices_to_pop = []
for (i, ep) in enumerate(element_paths)
    ce = PhysiCellModelManager.retrieveElement(xml_doc, ep; required=false)
    test_fn = !isnothing #! default test function
    if ep in paths_not_in_template
        test_fn = isnothing
        push!(indices_to_pop, i)
    elseif ep in paths_to_skip
        push!(indices_to_pop, i)
    else
        push!(paths_to_skip, ep) #! do not vary this parameter two times!
    end
    if (@test test_fn(ce)) isa Test.Fail
        println("Element $(ep) was not retrieved as expected. Expected to get $(test_fn)")
    end
end
free(xml_doc)
for i in reverse(indices_to_pop)
    popat!(element_paths, i)
end

@test_throws ArgumentError configPath("not_a_par")
@test_throws ArgumentError configPath(cell_type, "not_a_par")
@test_throws ArgumentError configPath(cell_type, "not_a_tag", "par")
@test_throws ArgumentError configPath(cell_type, "apoptosis", "duration", 0)
@test_throws ArgumentError configPath("too", "many", "args", "for", "configPath")
@test_throws ArgumentError configPath(cell_type, "apoptosis", "not_a_death_par")
@test_throws ArgumentError configPath(cell_type, "necrosis", "not_a_death_par")

discrete_variations = []
for (i, xml_path) in enumerate(element_paths)
    if xml_path[end] == "number_of_cells"
        push!(discrete_variations, DiscreteVariation(xml_path, [1, 2]))
    else
        push!(discrete_variations, DiscreteVariation(xml_path, float(i)))
    end
end
@test_throws ArgumentError PhysiCellModelManager.phagocytosisPath(cell_type, :not_a_type)
push!(discrete_variations, DiscreteVariation(["overall", "max_time"], [12.0]))

out = run(inputs, discrete_variations; n_replicates=n_replicates)

@test out.trial isa Sampling
@test length(out.trial) == prod(length.(discrete_variations)) * n_replicates
@test out.n_success == length(out.trial)

## test the in place functions
reference_monad = out.trial.monads[1]

monads = Monad[]
avs = AbstractVariation[]
avs = domainVariations((x_min=-78.1, x_max=78.1, y_min=-30.1, y_max=30.1, z_min=-10.1, z_max=10.1))
monad = createTrial(reference_monad, avs; n_replicates=n_replicates)
push!(monads, monad)

avs = domainVariations((min_x=[-78.2, -78.3], maxy=[30.2, 30.3]), covary=true)
sampling = createTrial(reference_monad, avs; n_replicates=n_replicates)
append!(monads, sampling.monads)

@test_throws ArgumentError domainVariations((x=70, ))
@test_throws AssertionError domainVariations((u_min=70, ))
@test_throws AssertionError domainVariations((x_min=[-78.2, -78.3, -78.4], maxy=[30.2, 30.3]); covary=true)

sampling_1 = Sampling(monads)

discrete_variations = DiscreteVariation[]
xml_path = configPath(cell_type, "speed")
push!(discrete_variations, DiscreteVariation(xml_path, [0.1, 1.0]))
push!(discrete_variations, DiscreteVariation(configPath(cell_type, "custom", "sample"), [0.1, 1.0]))
sampling_2 = createTrial(reference_monad, discrete_variations; n_replicates=n_replicates)

trial = Trial([sampling_1, sampling_2])

out = run(trial; force_recompile=false)
@test out.n_success == length(trial)

hashBorderPrint("SUCCESSFULLY VARIED CONFIG PARAMETERS!")

discrete_variations = []

xml_path = rulePath("default", "cycle entry", "decreasing_signals", "max_response")
push!(discrete_variations, DiscreteVariation(xml_path, [0.0, 1e-8]))
xml_path = rulePath("default", "cycle entry", "decreasing_signals", "signal:name:pressure", "half_max")
push!(discrete_variations, DiscreteVariation(xml_path, [0.25, 0.75]))

out = run(reference_monad, discrete_variations; n_replicates=n_replicates)

@test out.n_success == length(out.trial)

hashBorderPrint("SUCCESSFULLY VARIED RULESETS PARAMETERS!")

discrete_variations = []
xml_path = configPath(cell_type, "speed")
push!(discrete_variations, DiscreteVariation(xml_path, [0.1, 1.0]))
xml_path = rulePath("default", "cycle entry", "decreasing_signals", "signal:name:pressure", "half_max")
push!(discrete_variations, DiscreteVariation(xml_path, [0.3, 0.6]))

out = run(reference_monad, discrete_variations; n_replicates=n_replicates)
@test out.n_success == length(out.trial)

hashBorderPrint("SUCCESSFULLY VARIED CONFIG AND RULESETS PARAMETERS!")

# one last set of tests for coverage
discrete_variations = DiscreteVariation[]
push!(discrete_variations, DiscreteVariation(configPath(cell_type, "attack", cell_type), [0.1]))

out = run(reference_monad, discrete_variations; n_replicates=n_replicates)
@test out.n_success == length(out.trial)

@test isnothing(PhysiCellModelManager.prepareVariedInputFolder(:custom_code, Sampling(1))) #! returns nothing because custom codes is not varied
@test_throws ArgumentError PhysiCellModelManager.shortLocationVariationID(:not_a_location)
@test_nowarn PhysiCellModelManager.ModelManager.shortVariationName(:intracellular, "not_a_var")
@test_nowarn PhysiCellModelManager.ModelManager.shortVariationName(:intracellular, "intracellular_variation_id")
@test_throws ArgumentError PhysiCellModelManager.ModelManager.shortVariationName(:not_a_location, "not_a_var")

xml_doc = parse_file(path_to_xml)
xml_path = ["not", "a", "path"]
@test_throws ArgumentError PhysiCellModelManager.retrieveElement(xml_doc, xml_path)

# test the xml rules extended
xml_path = rulePath("increasing_partial_hill", "custom:sample", "increasing_signals", "max_response")
vals = [0.1, 1.0]
dv = DiscreteVariation(xml_path, vals)

config_folder = rules_folder = custom_code_folder = ic_cell_folder = "template_xml_rules_extended"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rules_folder, ic_cell=ic_cell_folder)
sampling = createTrial(inputs, dv)
PhysiCellModelManager.prepareVariedInputFolder(:rulesets_collection, sampling)
run(sampling)

# test that a bad path throws an error
cell_definition = "increasing_partial_hill"
xml_path = PhysiCellModelManager.cyclePath(cell_definition, "phase_transition_rates")
@test_throws AssertionError createTrial(inputs, DiscreteVariation(xml_path, [0.1, 1.0]))

xml_path = PhysiCellModelManager.phenotypePath(cell_definition, "volume")
@test_throws AssertionError createTrial(inputs, DiscreteVariation(xml_path, [0.1, 1.0]))

xml_path = ["save", "SVG", "plot_substrate", "min_conc"]
@test_throws AssertionError createTrial(inputs, DiscreteVariation(xml_path, [0.1, 1.0]))
################## prepareBaseFile on unselected input folders ##################
#
# Regression: `prepareBaseFile` tested `location == :rulesets_collection` before the
# `ismissing(basename)` guard, so an unselected ("") rulesets folder skipped the `nothing` path
# that every other location takes. It went on to look for base_rulesets.csv under a path with no
# folder component and tripped an assertion inside PhysiCellXMLRules that named neither the
# location nor the folder -- uncatchable in any useful way by a GUI.

# an unselected optional location has no folder to prepare, whatever the location is
for loc in [:rulesets_collection, :ic_cell, :ic_ecm, :intracellular]
    unselected = PhysiCellModelManager.InputFolder(loc, -1, "")
    @test ismissing(unselected.basename)
    @test isnothing(PhysiCellModelManager.prepareBaseFile(unselected))
end

# a selected rulesets folder still resolves to its base XML, and generates it when absent
selected = PhysiCellModelManager.InputFolder(:rulesets_collection, -1, "0_template")
path_to_base_xml = PhysiCellModelManager.prepareBaseFile(selected)
@test !isnothing(path_to_base_xml)
@test isfile(path_to_base_xml)
@test basename(path_to_base_xml) == "base_rulesets.xml"

# a selected folder holding neither base_rulesets file is refused by InputFolder itself, before
# prepareBaseFile is reached -- which is why PCMM adds no second check for that case
let probe = "empty-rules-probe"
    mkpath(PhysiCellModelManager.locationPath(:rulesets_collection, probe))
    @test_throws ErrorException PhysiCellModelManager.InputFolder(:rulesets_collection, -1, probe)
    rm(PhysiCellModelManager.locationPath(:rulesets_collection, probe); recursive=true, force=true)
end

################## configPath: motility scalars are not options ##################
#
# Regression: the three-token motility branch sent every third token through `<options>`, so
# `configPath("default", "motility", "speed")` resolved to `.../motility/options/speed`, which is
# not in the schema. `<motility>` holds speed/persistence_time/migration_bias directly and reserves
# `<options>` for enabled/use_2D/chemotaxis. The two-token spelling was always correct, so the two
# disagreed -- which is the sharpest way to state the bug, and the cheapest way to catch it again.

for tag in ["speed", "persistence_time", "migration_bias"]
    two_token = PhysiCellModelManager.configPath("default", tag)
    three_token = PhysiCellModelManager.configPath("default", "motility", tag)
    @test two_token == three_token
    @test three_token == PhysiCellModelManager.motilityPath("default", tag)
    @test !("options" in three_token)
end

# ...while the genuine options still go through <options>
for tag in ["enabled", "use_2D"]
    path = PhysiCellModelManager.configPath("default", "motility", tag)
    @test path == PhysiCellModelManager.motilityPath("default", "options", tag)
    @test "options" in path
end

# and the chemotaxis branches are untouched
@test PhysiCellModelManager.configPath("default", "chemotaxis", "substrate") ==
      PhysiCellModelManager.motilityPath("default", "options", "chemotaxis", "substrate")

# An unrecognized tag in either closed set is rejected by name, matching how every other configPath
# branch handles a token it cannot honour. Previously it resolved into <options> and failed later
# with "Element not found", pointing at the XML rather than at the call.
@test_throws ArgumentError PhysiCellModelManager.configPath("default", "motility", "not_a_motility_tag")
@test_throws ArgumentError PhysiCellModelManager.configPath("default", "chemotaxis", "not_a_chemotaxis_tag")

# ...but advanced_chemotaxis stays open-ended: its third token is a substrate name, not a fixed tag.
@test PhysiCellModelManager.configPath("default", "advanced_chemotaxis", "some_substrate") ==
      PhysiCellModelManager.motilityPath("default", "options", "advanced_chemotaxis",
                                         "chemotactic_sensitivities",
                                         "chemotactic_sensitivity:substrate:some_substrate")
@test PhysiCellModelManager.configPath("default", "advanced_chemotaxis", "enabled") ==
      PhysiCellModelManager.motilityPath("default", "options", "advanced_chemotaxis", "enabled")
