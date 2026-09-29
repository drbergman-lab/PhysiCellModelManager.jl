# [Running simulations](@id running_simulations_man)

This page covers launching a trial, spreading its simulations across local cores, and handing them
to a SLURM cluster instead.

## Run a trial

!!! tiergloss
    [`createTrial`](@ref) builds the trial and records it in the database; [`run`](@ref) launches
    every simulation in it that has not already completed. `n_replicates` and `use_previous` are
    `createTrial` keyword arguments, not `run` ones — they decide how many replicates each
    parameter set gets and whether existing matching simulations count toward that number.

!!! tierwhy
    `use_previous = true` (the default) is why re-running a script is cheap: a parameter set that
    already has enough completed simulations contributes none, so nothing is recomputed. Set it to
    `false` when you want fresh replicates regardless of what is on disk.

```julia
inputs = InputFolders("0_template", "0_template")
dv = DiscreteVariation(configPath("max_time"), [1440.0, 2880.0])

sampling = createTrial(inputs, dv; n_replicates = 3, use_previous = true)
run(sampling)

run(inputs, dv; n_replicates = 3)   # create and run in one call
```

!!! tierdev
    **Return value.** `run` returns an [`MMOutput`](@ref) — fields `trial`, `n_scheduled`,
    `n_success`; `PCMMOutput` is an alias for the same type. `n_scheduled == 0` on a second run
    means everything was already there.

    **Per simulation.** `run` drives one worker task per pending simulation, each calling
    [`runSimulation`](@ref ModelManager.runSimulation), which builds the command, creates the
    output folder, redirects `output.log`/`output.err`, and returns a
    [`SimulationProcess`](@ref ModelManager.SimulationProcess). [`wasSuccessful`](@ref) is the predicate on that struct; the
    simulator hooks receive it rather than a [`Simulation`](@ref).

## Where the output lands

!!! tiergloss
    Each simulation writes into `data/outputs/simulations/<simulation_id>/` — see
    [Data directory structure](@ref data_directory_man). [`pathToOutputFolder`](@ref) builds that
    path from a raw ID, a [`Simulation`](@ref), or the [`SimulationProcess`](@ref ModelManager.SimulationProcess) a
    `post_processor` hook receives, so nothing downstream has to hard-code the layout.

```julia
pathToOutputFolder(5)
pathToOutputFolder(Simulation(5))
```

## Run several at once locally

!!! tiergloss
    [`setNumberOfParallelSims`](@ref) caps how many simulations run concurrently on this machine.
    It starts from the `PCMM_NUM_PARALLEL_SIMS` environment variable, or 1 if that is unset.

!!! tierwhy
    Each PhysiCell simulation is itself multithreaded (`omp_num_threads` in its config), so the
    useful cap is roughly your core count divided by that thread count. Setting the environment
    variable instead keeps the number out of the script, which matters when the same script runs
    on a laptop and on a cluster node.

```julia
setNumberOfParallelSims(8)
run(sampling)
```

## Run on an HPC

!!! tiergloss
    In HPC mode, `run` submits each simulation to SLURM with `sbatch` instead of starting it on this
    machine. HPC mode is detected: [`initializeModelManager`](@ref) calls
    [`isRunningOnHPC`](@ref), which probes for the `sbatch` command, and turns HPC mode on if it
    finds it. The banner printed at initialization reports the result on its `Running on HPC:`
    line (`true` or `false`). [`useHPC`](@ref)`(true)` or `useHPC(false)` overrides the detection
    for the rest of the session.

    [`setJobOptions`](@ref) merges entries into the `sbatch` options dictionary, each becoming a
    `--key=value` flag. A value may be a function of the [`Simulation`](@ref) about to be
    submitted, so an option can follow a varied parameter.

    **Leave `cpus-per-task` alone.** PCMM sets it per job from that simulation's own
    `parallel/omp_num_threads`, so the allocation matches the threads PhysiCell will start. A value
    you pass through [`setJobOptions`](@ref) replaces PCMM's and is never overridden — and a job
    given fewer CPUs than the config asks for time-slices its threads on one core, running several
    times slower with nothing in any log to say so.

!!! tierwhy
    `useHPC` pins the choice across later calls to `initializeModelManager` because each call
    probes for `sbatch` again; without the pin, a re-initialization would undo a deliberate
    `useHPC(false)` on a machine that happens to have SLURM installed. The keys PCMM renders
    itself — `wrap`, `output`, `error`, `wait`, `parsable`, `chdir` — are refused by
    `setJobOptions` with an `ArgumentError`.

```julia
useHPC()                                  # useHPC(false) forces local runs
setJobOptions(Dict("time" => "02:00:00",
                   "mem" => "8G",
                   "partition" => "shared"))
run(sampling)
```

!!! tierdev
    **CPUs per job.** The `cpus-per-task` above is PCMM's method on ModelManager's
    [`simulationThreads`](@ref ModelManager.simulationThreads) hook, in `src/simulator_interface.jl`;
    `defaultJobOptions` is what asks it. A config element that cannot be read falls back to 1 with
    one warning rather than failing the submission. The [Simulator interface](@ref simulator_interface_dev)
    page has the rest of the hooks.

!!! tierjournal "2026-09-05 — `cpus-per-task` follows `omp_num_threads`"
    **Decided:** PCMM answers ModelManager's `simulationThreads` hook with
    `parallel/omp_num_threads` read from the simulation's own variation record, so a varied thread
    count is honored and every job is allocated the CPUs PhysiCell will actually use. A config
    whose element cannot be read falls back to 1 with one warning rather than failing the
    submission, and a `cpus-per-task` you set yourself still wins.

!!! tierjournal "2026-08-05 — Compiling for `x86-64` on a cluster"
    **Decided:** [`initializeModelManager`](@ref) sets the compile flag to `-march=x86-64` when the
    session is in HPC mode and `-march=native` otherwise. The question a compile has to answer is
    whether this binary will later be executed by a machine that did not build it, and a batch
    scheduler is exactly the thing that does that: a `-march=native` binary built on a newer login
    node dies with an illegal-instruction (SIGILL) crash on an older compute node. The binary is
    cached across sessions, so the choice cannot be revisited at run time.
    **Rejected:** `x86-64-v3`, which is the Haswell feature level and so reintroduces that crash on
    older nodes; and parsing `scontrol show nodes` to detect a heterogeneous partition.
    **Open:** a non-Slurm scheduler (PBS, LSF, SGE) is not probed for and still gets `native`, and a
    mixed-architecture cluster — x86 login node, non-x86 compute nodes — is unsupported: run Julia
    on a node of the same architecture as your compute partition.

!!! tiergloss
    A submitted job reports its exit code by writing a sentinel file that the submitting worker
    polls for; [`setHPCCompletionOptions`](@ref) adjusts the timings of that protocol.

    The sentinel files are written to `data/outputs/.hpc_done` unless the environment variable
    `MODELMANAGER_HPC_DONE_DIR` is set (and non-empty), in which case they go to the directory it
    names. That directory must be writable by the compute nodes and readable by the node that
    submits the jobs, the one running Julia. The variable is read once, when
    [`initializeModelManager`](@ref) runs, so set it before initializing; PCMM can initialize a
    project as soon as it is loaded, so the shell that starts Julia is the safest place. A
    directory that cannot be created or written makes initialization throw an `ArgumentError`.

!!! tierwhy
    The timings are the fields of [`HPCCompletionOptions`](@ref ModelManager.HPCCompletionOptions):
    `submit_retry_period` (how long a transiently refused submission is retried), `poll_interval`
    (how often a worker checks for its own sentinel), `reap_interval` (how long one `squeue` answer
    is shared among waiting workers), and `grace_period` (how long a job may be missing from the
    queue with no sentinel before it is declared failed).

    `grace_period` is the one to raise first. It must exceed your filesystem's worst-case
    directory-attribute staleness: if a compute node writes the sentinel but this node cannot see
    it within the grace period, a successful simulation is recorded as failed.

```julia
setHPCCompletionOptions(grace_period = 600.0)   # slow shared filesystem
```

```bash
export MODELMANAGER_HPC_DONE_DIR=/scratch/$USER/hpc_done   # before starting Julia
```
