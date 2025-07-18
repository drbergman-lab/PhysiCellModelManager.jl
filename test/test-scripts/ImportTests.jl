filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "immune_sample"
custom_code_folder = rulesets_collection_folder = ic_cell_folder = "immune_function"

path_to_project = joinpath("PhysiCell", "sample_projects", "immune_function")

dest = Dict()
dest["config"] = config_folder

src = Dict()
src["config"] = "PhysiCell_settings.xml"
src["rulesets_collection"] = "cell_rules.csv"
success = importProject(path_to_project, src, dest)
@test success

inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_cell=ic_cell_folder)

discrete_variations = []
push!(discrete_variations, DiscreteVariation(configPath("max_time"), 12.0))
push!(discrete_variations, DiscreteVariation(configPath("full_data"), 6.0))
push!(discrete_variations, DiscreteVariation(configPath("svg_save"), 6.0))

simulation_from_import = createTrial(inputs, discrete_variations; n_replicates=1) #! save this for PopulationTests.jl and GraphsTests.jl, etc.

out = run(simulation_from_import; force_recompile=false)

@test out.n_success == length(simulation_from_import)

success = importProject(path_to_project, src, dest)
@test success
@test isdir(pcvct.locationPath(:config, "immune_sample_1"))

src["rules"] = "not_rules.csv"
success = importProject(path_to_project, src, dest)
@test !success

path_to_fake_project = joinpath("PhysiCell", "sample_projects", "not_a_project")
success = importProject(path_to_fake_project)
@test !success

path_to_project = joinpath("PhysiCell", "sample_projects", "template")
success = importProject(path_to_project)
@test success

# intentionally sabotage the import
path_to_bad_project = joinpath("PhysiCell", "sample_projects", "bad_template")
cp(path_to_project, joinpath("PhysiCell", "sample_projects", "bad_template"))

path_to_main = joinpath("PhysiCell", "sample_projects", "bad_template", "main.cpp")
lines = readlines(path_to_main)
idx = findfirst(x->contains(x, "argument_parser"), lines)
lines[idx] = "    //no longer parsing because this is now a bad project"
idx = findfirst(x->contains(x, "// load and parse settings file(s)"), lines)
lines[idx] = "    //no longer loading settings because this is now a bad project"
open(path_to_main, "w") do f
    for line in lines
        println(f, line)
    end
end

path_to_custom_cpp = joinpath("PhysiCell", "sample_projects", "bad_template", "custom_modules", "custom.cpp")
lines = readlines(path_to_custom_cpp)
idx = findfirst(x->contains(x, "load_initial_cells"), lines)
lines[idx] = "    //no longer loading initial cells because this is now a bad project"
open(path_to_custom_cpp, "w") do f
    for line in lines
        println(f, line)
    end
end

success = importProject(path_to_bad_project)
@test !success

# import the ecm project to actually use
path_to_project = joinpath("PhysiCell", "sample_projects", "template-ecm")
success = importProject(path_to_project)
@test success

# import the dirichlet conditions from file project
path_to_project = joinpath("PhysiCell", "sample_projects", "dirichlet_from_file")
success = importProject(path_to_project)
@test success

# import the combined sbml project
path_to_project = joinpath("PhysiCell", "sample_projects_intracellular", "combined", "template-combined")
src = Dict("intracellular" => "sample_combined_sbmls.xml")
success = importProject(path_to_project, src)
@test success

path_to_project = joinpath("PhysiCell", "sample_projects_intracellular", "ode", "ode_energy")
success = importProject(path_to_project)
@test success

# import the template xml rules (simple) project
path_to_project = joinpath("PhysiCell", "sample_projects", "template_xml_rules")
success = importProject(path_to_project)
@test success

# import the template xml rules (extended) project
path_to_project = joinpath("PhysiCell", "sample_projects", "template_xml_rules_extended")
success = importProject(path_to_project)
@test success