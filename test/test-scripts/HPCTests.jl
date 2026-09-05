filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

PhysiCellModelManager.useHPC()

simulation = Simulation(1)
monad = Monad(simulation)

# PCMM's job is now only to say what to run; ModelManager v0.9.0 owns the sbatch wrapping, the
# submission and the wait, and `prepareHPCCommand` is gone. So the assertions about `--wrap` and
# `--wait` moved to ModelManager with the code -- `--wait` in particular no longer exists, since #47
# replaced polling with a completion sentinel on the shared filesystem. What is left to check here is
# the contract PCMM must satisfy.
cmd_local = PhysiCellModelManager.prepareSimulationCommand(simulation)
spec = PhysiCellModelManager.ModelManager.SimulationSpec(simulation, monad.id)

#! `simulationCommand` is what PCMM implements now, and it must hand back exactly the command.
@test PhysiCellModelManager.simulationCommand(PhysiCellModelManager.simulator(), spec) == cmd_local

#! No environment on the Cmd. ModelManager rejects one with an ArgumentError, because `Cmd.env`
#! replaces the environment while `sbatch --export` extends it -- so a command carrying an env would
#! behave one way locally and the opposite on a cluster. `dir` is set and is honoured on both paths.
@test isnothing(cmd_local.env)
@test cmd_local.dir == PhysiCellModelManager.physicellDir()

# gh actions runners are not expected to have `sbatch` installed, so the submission fails here
simulation_process = PhysiCellModelManager.ModelManager.runSimulation(PhysiCellModelManager.simulator(), spec)
@test isnothing(simulation_process.process)
@test !simulation_process.success
#! ...but a command *was* built, which is what `cmd` records and what distinguishes this from a
#! simulation that never launched at all.
@test !isnothing(simulation_process.cmd)

# test postSimulationCleanup does not crash on a failed process whose output.err was never
# created (e.g. an sbatch submission failure on HPC before the job ever ran and redirected
# its stderr to output.err)
path_to_err = joinpath(PhysiCellModelManager.trialFolder(simulation), "output.err")
rm(path_to_err; force=true)
fake_process = Base.run(pipeline(ignorestatus(`false`)); wait=true)
#! Five arguments: `cmd` must be set, because `postSimulationCleanup` now reads it to answer "did
#! this ever launch?". A four-argument construction defaults `cmd` to `nothing`, which correctly
#! means "never launched" and would skip the annotation asserted below.
fake_simulation_process = PhysiCellModelManager.SimulationProcess(simulation, monad.id, fake_process, false, cmd_local)
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
#! What PCMM can still check is that the options reach the globals `setJobOptions` writes to,
#! including the callable form that is resolved per simulation. Asserting they appear in the
#! generated `sbatch` line is no longer PCMM's to make: `prepareHPCCommand` is gone in v0.9.0 and
#! ModelManager builds and tests that command itself.
#! (These were `@assert`, which does not register as a test failure at all.)
@test PhysiCellModelManager.mm_globals().sbatch_options["cpus-per-task"] == "2"
@test PhysiCellModelManager.mm_globals().sbatch_options["job-name"](78) == "test_78"

deleteSimulationsByStatus("Failed"; user_check=false)