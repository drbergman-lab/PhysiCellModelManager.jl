using SQLite

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

sim_id = simulationIDs()[1]
fake_python_path = "fake_python_path"
fake_studio_path = "fake_studio_path"
@test_throws ArgumentError PhysiCellModelManager.resolveStudioGlobals(missing, missing)
@test_throws ArgumentError PhysiCellModelManager.resolveStudioGlobals(fake_python_path, missing)

#! Failure mode 1: the python executable cannot be spawned. `run` raises Base.IOError here.
@test_throws PhysiCellModelManager.PCMMStudioLaunchError runStudio(sim_id; python_path=fake_python_path, studio_path=fake_studio_path)

@test PhysiCellModelManager.simulator().path_to_python == fake_python_path
@test PhysiCellModelManager.simulator().path_to_studio == fake_studio_path

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
@test_throws PhysiCellModelManager.PCMMStudioLaunchError runStudio(pcmm_output; python_path=fake_python_path, studio_path=fake_studio_path)

#! put the file back
mv(path_to_dummy_parsed_rules, path_to_parsed_rules)

#! Failure mode 2: the interpreter runs but exits non-zero, which `run` reports as a
#! ProcessFailedException -- a type with no `.code` field. Reading `.code` unconditionally used to
#! raise `FieldError: type ProcessFailedException has no field code` from inside the error handler,
#! so the user never saw why Studio failed. No test covered this path, because every existing case
#! passed a nonexistent interpreter and therefore took the IOError branch above.
#! Julia stands in for python: it exists on every platform running this suite, and asking it to run
#! a .py that is not there exits non-zero.
real_but_wrong_interpreter = joinpath(Sys.BINDIR, Base.julia_exename())
@test isfile(real_but_wrong_interpreter)
err = try
    runStudio(sim_id; python_path=real_but_wrong_interpreter, studio_path=fake_studio_path)
    nothing
catch e
    e
end
@test err isa PhysiCellModelManager.PCMMStudioLaunchError
@test err.cause isa ProcessFailedException
@test !isempty(sprint(showerror, err))

#! Both failure modes are PCMMExceptions, so a GUI can catch the family without knowing either.
@test err isa PhysiCellModelManager.PCMMException

#! The temporary Studio inputs are cleaned up even when the launch fails.
simulation_output_folder = PhysiCellModelManager.pathToOutputFolder(sim_id)
@test !isfile(joinpath(simulation_output_folder, "PhysiCell_settings_temp.xml"))
