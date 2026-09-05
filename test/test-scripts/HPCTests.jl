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

# gh actions runners are not expected to have `sbatch` installed. Since ModelManager 0.10 a
# submission `sbatch` refuses -- including `sbatch` not being invocable at all -- is not a failed
# simulation: no job ran, so nothing is recorded against the simulation and `run` fails fast with
# the scheduler's message instead. A direct caller of `runSimulation` sees the exception itself.
@test_throws PhysiCellModelManager.ModelManager._SubmissionRefused PhysiCellModelManager.ModelManager.runSimulation(PhysiCellModelManager.simulator(), spec)

#! PhysiCell reads its OpenMP thread count from the config, so PCMM asks SLURM for that many CPUs
#! per job by default; the test config sets 6. Installed at initialization, resolved per simulation,
#! and only when the user has not set `cpus-per-task` themselves (checked below).
@test PhysiCellModelManager.mm_globals().sbatch_options["cpus-per-task"](simulation.id) == 6
@test PhysiCellModelManager._ompNumThreads(simulation.id) == 6

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

#! The SLURM shape, which is the case the `process` -> `cmd` switch exists for: the work ran on a
#! compute node, so `process === nothing` while `cmd` is set. Guarding on `process` would early-return
#! here and skip pruning and err-file handling for an entire campaign, and reaching through `p.cmd`
#! would throw. The live-`Process` case above passes against either version of the guard, so this is
#! the assertion that actually pins the fix.
slurm_shaped = PhysiCellModelManager.SimulationProcess(simulation, monad.id, nothing, false, cmd_local)
@test isnothing(slurm_shaped.process) && !isnothing(slurm_shaped.cmd)
@test_nowarn PhysiCellModelManager.postSimulationCleanup(PhysiCellModelManager.simulator(), slurm_shaped)
@test isfile(path_to_err)
#! PhysiCell's own command, not an `sbatch` wrapper -- `p.cmd` would have given the latter, when it
#! did not throw outright.
@test contains(read(path_to_err, String), "Execution command: ")
@test contains(read(path_to_err, String), string(cmd_local))
rm(path_to_err; force=true)

#! ...and `cmd === nothing` still means "never launched": the early return leaves no annotation.
never_launched = PhysiCellModelManager.SimulationProcess(simulation, monad.id, nothing, false, nothing)
@test_nowarn PhysiCellModelManager.postSimulationCleanup(PhysiCellModelManager.simulator(), never_launched)
@test !isfile(path_to_err)

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
#! Re-initializing does not clobber a user's own `cpus-per-task`.
PhysiCellModelManager._installDefaultJobOptions()
@test PhysiCellModelManager.mm_globals().sbatch_options["cpus-per-task"] == "2"
#! ModelManager's reserved keys are refused at set time.
@test_throws ArgumentError PhysiCellModelManager.setJobOptions(Dict("wrap" => "echo"))

deleteSimulationsByStatus("Failed"; user_check=false)