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
@test importProject(path_to_project; src=src, dest=dest) isa InputFolders

inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_cell=ic_cell_folder)

discrete_variations = []
push!(discrete_variations, DiscreteVariation(configPath("max_time"), 12.0))
push!(discrete_variations, DiscreteVariation(configPath("full_data"), 6.0))
push!(discrete_variations, DiscreteVariation(configPath("svg_save"), 6.0))

simulation_from_import = createTrial(inputs, discrete_variations; n_replicates=1) #! save this for PopulationTests.jl and GraphsTests.jl, etc.

out = run(simulation_from_import; force_recompile=false)

@test out.n_success == length(simulation_from_import)

@test importProject(path_to_project; src=src, dest=dest) isa InputFolders
@test isdir(PhysiCellModelManager.locationPath(:config, "immune_sample_1"))

src["rules"] = "not_rules.csv"
@test importProject(path_to_project; src=src, dest=dest) |> isnothing

path_to_fake_project = joinpath("PhysiCell", "sample_projects", "not_a_project")
@test importProject(path_to_fake_project) |> isnothing

path_to_project = joinpath("PhysiCell", "sample_projects", "template")
folder_name = "unique-project-name"
@test importProject(path_to_project; dest=folder_name) isa InputFolders
for loc in [:config, :custom_code, :rulesets_collection, :ic_substrate]
    @test isdir(PhysiCellModelManager.locationPath(loc, folder_name))
end

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

@test importProject(path_to_bad_project) |> isnothing

# import the ecm project to actually use
path_to_project = joinpath("PhysiCell", "sample_projects", "template-ecm")
@test importProject(path_to_project) isa InputFolders

# import the dirichlet conditions from file project
path_to_project = joinpath("PhysiCell", "sample_projects", "dirichlet_from_file")
@test importProject(path_to_project) isa InputFolders

# import the combined sbml project
path_to_project = joinpath("PhysiCell", "sample_projects_intracellular", "combined", "template-combined")
src = Dict("intracellular" => "sample_combined_sbmls.xml")
@test importProject(path_to_project; src=src) isa InputFolders

path_to_project = joinpath("PhysiCell", "sample_projects_intracellular", "ode", "ode_energy")
@test importProject(path_to_project) isa InputFolders

# import the template xml rules (simple) project
path_to_project = joinpath("PhysiCell", "sample_projects", "template_xml_rules")
@test importProject(path_to_project) isa InputFolders

# import the template xml rules (extended) project
path_to_project = joinpath("PhysiCell", "sample_projects", "template_xml_rules_extended")
@test importProject(path_to_project) isa InputFolders

# dest depwarn of deprecated method
path_to_project = joinpath("PhysiCell", "sample_projects", "template")
src = Dict()
dest = Dict("rules" => "new-rules-folder")
@test_warn "`importProject` with more than one positional argument is deprecated. Use the method `importProject(path_to_project; src=Dict(), dest=Dict())` instead." importProject(path_to_project, src, dest)
@test isdir(PhysiCellModelManager.locationPath(:rulesets_collection, "new-rules-folder"))