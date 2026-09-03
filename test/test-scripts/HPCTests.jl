filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

PhysiCellModelManager.useHPC()

simulation = Simulation(1)
monad = Monad(simulation)

cmd_local = PhysiCellModelManager.prepareSimulationCommand(simulation)
cmd_local_str = string(Cmd(cmd_local.exec))
cmd_local_str = strip(cmd_local_str, '`')
cmd_hpc = PhysiCellModelManager.ModelManager.prepareHPCCommand(cmd_local, simulation.id)

cmd_string = string(cmd_hpc)
cmd_string = strip(cmd_string, '`')

@test startswith(cmd_string, "sbatch")
@test contains(cmd_string, "--wrap=$(cmd_local_str)")
@test contains(cmd_string, "--wait")

# test prep of command
# gh actions runners not expected to have `sbatch` installed
spec = PhysiCellModelManager.ModelManager.SimulationSpec(simulation, monad.id)
simulation_process = PhysiCellModelManager.ModelManager.runSimulation(PhysiCellModelManager.simulator(), spec)
@test isnothing(simulation_process.process)
@test !simulation_process.success

# test postSimulationCleanup does not crash on a failed process whose output.err was never
# created (e.g. an sbatch submission failure on HPC before the job ever ran and redirected
# its stderr to output.err)
path_to_err = joinpath(PhysiCellModelManager.trialFolder(simulation), "output.err")
rm(path_to_err; force=true)
fake_process = Base.run(pipeline(ignorestatus(`false`)); wait=true)
fake_simulation_process = PhysiCellModelManager.SimulationProcess(simulation, monad.id, fake_process, false)
@test_nowarn PhysiCellModelManager.postSimulationCleanup(PhysiCellModelManager.simulator(), fake_simulation_process)
@test contains(read(path_to_err, String), "no output.err file was found")
rm(path_to_err; force=true)

# ModelManager 0.9 changed rm_hpc_safe: it now attempts the real removal first and stages only
# what it could not remove, returning :removed or :staged. Before, every HPC deletion was
# relocated into data/.trash and left there, so a cluster project never reclaimed any space.
# These tests assert the 0.9 contract.

# a missing path with force=false still throws, exactly as rm does
@test_throws Base.IOError PhysiCellModelManager.rm_hpc_safe("not_a_file.txt")

# ...and force=true makes it a no-op, as rm does
@test PhysiCellModelManager.rm_hpc_safe("not_a_file.txt"; force=true) == :removed

# a file that does exist is really removed, not staged
path_to_dummy_file = joinpath(PhysiCellModelManager.dataDir(), "test.txt")
open(path_to_dummy_file, "w") do f
    write(f, "test")
end
#! `:removed` is returned only on the branch where `rm` itself succeeded, so it already proves
#! nothing was staged. Asserting the absence of `data/.trash` would additionally couple this test
#! to whatever every other testset did with the same data directory.
@test PhysiCellModelManager.rm_hpc_safe(path_to_dummy_file) == :removed
@test !isfile(path_to_dummy_file)

# NOTE: the :staged branch is deliberately uncovered. Reaching it requires rm to fail on a path
# that still exists afterwards -- a busy or held file -- which cannot be produced portably. The
# old tests appeared to cover it only because staging was unconditional; under 0.9 they would
# assert something that never happens on a healthy filesystem.

# revert back to not using HPC for remainder of tests
PhysiCellModelManager.useHPC(false)

new_hpc_options = Dict("cpus-per-task" => "2",
                       "job-name" => simulation_id -> "test_$(simulation_id)")
PhysiCellModelManager.setJobOptions(new_hpc_options)
@test PhysiCellModelManager.mm_globals().sbatch_options["cpus-per-task"] == "2"
hpc_command = PhysiCellModelManager.ModelManager.prepareHPCCommand(cmd_local, 78)

cmd_string = string(hpc_command)
cmd_string = strip(cmd_string, '`')
@assert contains(cmd_string, "--cpus-per-task=2")
@assert contains(cmd_string, "--job-name=test_78")

deleteSimulationsByStatus("Failed"; user_check=false)