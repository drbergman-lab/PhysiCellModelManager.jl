using Dates

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

PhysiCellModelManager.useHPC()

simulation = Simulation(1)
monad = Monad(simulation)

cmd_local = PhysiCellModelManager.prepareSimulationCommand(simulation, monad.id, true, false)
cmd_local_str = string(Cmd(cmd_local.exec))
cmd_local_str = strip(cmd_local_str, '`')
cmd_hpc = PhysiCellModelManager.prepareHPCCommand(cmd_local, simulation.id)

cmd_string = string(cmd_hpc)
cmd_string = strip(cmd_string, '`')

@test startswith(cmd_string, "sbatch")
@test contains(cmd_string, "--wrap=$(cmd_local_str)")
@test contains(cmd_string, "--wait")

# test prep of command
# gh actions runners not expected to have `sbatch` installed
@test_throws Base.IOError PhysiCellModelManager.SimulationProcess(simulation)

# test hpc removal of file that does not exist
@test isnothing(PhysiCellModelManager.rm_hpc_safe("not_a_file.txt"))

# test hpc removal of file that does exist
current_time = Dates.now()
threshold_seconds = 15
end_of_day = DateTime(Dates.year(current_time), Dates.month(current_time), Dates.day(current_time), 23, 59, 59)
threshold_time = end_of_day - Second(threshold_seconds)
is_about_to_be_next_day = current_time >= threshold_time
if is_about_to_be_next_day
    #! if it's about to be the next day, wait until it is the next day
    sleep(threshold_seconds + 1)
end
path_to_dummy_file = joinpath(PhysiCellModelManager.dataDir(), "test.txt")
open(path_to_dummy_file, "w") do f
    write(f, "test")
end
PhysiCellModelManager.rm_hpc_safe(path_to_dummy_file)
@test joinpath(PhysiCellModelManager.dataDir(), ".trash", "data-$(Dates.format(now(), "yymmdd"))", "test.txt") |> isfile

# test hpc removal of file with same name
path_to_dummy_file = joinpath(PhysiCellModelManager.dataDir(), "test.txt")
open(path_to_dummy_file, "w") do f
    write(f, "test")
end
PhysiCellModelManager.rm_hpc_safe(path_to_dummy_file)
@test joinpath(PhysiCellModelManager.dataDir(), ".trash", "data-$(Dates.format(now(), "yymmdd"))", "test-1.txt") |> isfile

# revert back to not using HPC for remainder of tests
PhysiCellModelManager.useHPC(false)

new_hpc_options = Dict("cpus-per-task" => "2",
                       "job-name" => simulation_id -> "test_$(simulation_id)")
PhysiCellModelManager.setJobOptions(new_hpc_options)
@test PhysiCellModelManager.pcmm_globals.sbatch_options["cpus-per-task"] == "2"
hpc_command = PhysiCellModelManager.prepareHPCCommand(cmd_local, 78)

cmd_string = string(hpc_command)
cmd_string = strip(cmd_string, '`')
@assert contains(cmd_string, "--cpus-per-task=2")
@assert contains(cmd_string, "--job-name=test_78")
