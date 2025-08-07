using SQLite

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

sim_id = 1
fake_python_path = "fake_python_path"
fake_studio_path = "fake_studio_path"
@test_throws ArgumentError PhysiCellModelManager.resolveStudioGlobals(missing, missing)
@test_throws ArgumentError PhysiCellModelManager.resolveStudioGlobals(fake_python_path, missing)

@test_throws Base.IOError runStudio(sim_id; python_path=fake_python_path, studio_path=fake_studio_path)

@test PhysiCellModelManager.pcmm_globals.path_to_python == fake_python_path
@test PhysiCellModelManager.pcmm_globals.path_to_studio == fake_studio_path

#! test that the studio launches even when the rules file cannot be found
simulation_output_folder = PhysiCellModelManager.pathToOutputFolder(sim_id)
path_to_parsed_rules = joinpath(simulation_output_folder, "cell_rules_parsed.csv")
@test isfile(path_to_parsed_rules)
path_to_dummy_parsed_rules = joinpath(simulation_output_folder, "cell_rules_parsed__.csv")
@test !isfile(path_to_dummy_parsed_rules)
mv(path_to_parsed_rules, path_to_dummy_parsed_rules)
@test !isfile(path_to_parsed_rules)
@test isfile(path_to_dummy_parsed_rules)
pcmm_output = run(Simulation(sim_id))
@test_throws Base.IOError runStudio(pcmm_output; python_path=fake_python_path, studio_path=fake_studio_path)

#! put the file back
mv(path_to_dummy_parsed_rules, path_to_parsed_rules)