# [Running simulations](@id running_simulations_man)

This page covers launching a trial, spreading its simulations across local cores, and handing them
to a SLURM cluster instead.

## Run a trial

!!! tierwhy
    `use_previous = true` (the default) is why re-running a script is cheap: a parameter set that
    already has enough completed simulations contributes none, so nothing is recomputed. Set it to
    `false` when you want fresh replicates regardless of what is on disk.

!!! tiergloss
    [`createTrial`](@ref) builds the trial and records it in the database; [`run`](@ref) launches
    every simulation in it that has not already completed. `n_replicates` and `use_previous` are
    `createTrial` keyword arguments, not `run` ones — they decide how many replicates each
    parameter set gets and whether existing matching simulations count toward that number.

```julia
inputs = InputFolders("0_template", "0_template")
dv = DiscreteVariation(configPath("max_time"), [1440.0, 2880.0])

sampling = createTrial(inputs, dv; n_replicates = 3, use_previous = true)
run(sampling)

run(inputs, dv; n_replicates = 3)   # create and run in one call
```

!!! tierdev
    **Return value.** `run` returns an [`MMOutput`](@ref) — fields `trial`, `n_scheduled`,
    `n_success`. `PCMMOutput` is a deprecated alias kept for older scripts. `n_scheduled == 0` on a
    second run means everything was already there.

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

!!! tierwhy
    Each PhysiCell simulation is itself multithreaded (`omp_num_threads` in its config), so the
    useful cap is roughly your core count divided by that thread count. Setting the environment
    variable instead keeps the number out of the script, which matters when the same script runs
    on a laptop and on a cluster node.

!!! tiergloss
    [`setNumberOfParallelSims`](@ref) caps how many simulations run concurrently on this machine.
    It starts from the `PCMM_NUM_PARALLEL_SIMS` environment variable, or 1 if that is unset.

```julia
setNumberOfParallelSims(8)
run(sampling)
```

## Run on an HPC

!!! tierwhy
    [`initializeModelManager`](@ref) probes for `sbatch` on every call and sets HPC mode from what
    it finds, so a later re-initialization would otherwise undo a deliberate `useHPC(false)` on a
    machine that happens to have SLURM installed. `useHPC` pins the choice for the session and
    across those later calls. The keys PCMM renders itself — `wrap`, `output`, `error`, `wait`,
    `parsable`, `chdir` — are refused by `setJobOptions` with an `ArgumentError`.

!!! tiergloss
    [`useHPC`](@ref) pins simulations to SLURM submission for the session;
    [`setJobOptions`](@ref) merges entries into the `sbatch` options dictionary, each becoming a
    `--key=value` flag. A value may be a function of the [`Simulation`](@ref) about to be
    submitted, so an option can follow a varied parameter.

```julia
useHPC()                                  # useHPC(false) forces local runs
setJobOptions(Dict("time" => "02:00:00",
                   "mem" => "8G",
                   "partition" => "shared"))
run(sampling)
```

!!! tierwhy
    `grace_period` is the one to raise first. It must exceed your filesystem's worst-case
    directory-attribute staleness: if a compute node writes the sentinel but this node cannot see
    it within the grace period, a successful simulation is recorded as failed. The sentinel
    directory itself is deliberately not one of these options — it is `data/outputs/.hpc_done`
    unless `MODELMANAGER_HPC_DONE_DIR` says otherwise, and it is fixed for the session.

!!! tiergloss
    A submitted job reports its exit code by writing a sentinel file to a shared directory, which
    the submitting worker polls. [`setHPCCompletionOptions`](@ref) adjusts the timings of that
    protocol, which are the fields of [`HPCCompletionOptions`](@ref ModelManager.HPCCompletionOptions):
    `submit_retry_period` (how long a transiently refused submission is retried),
    `poll_interval` (how often a worker checks for its own sentinel), `reap_interval` (how long
    one `squeue` answer is shared among waiting workers), and `grace_period` (how long a job may
    be missing from the queue with no sentinel before it is declared failed).

```julia
setHPCCompletionOptions(grace_period = 600.0)   # slow shared filesystem
```

!!! tierdev
    **CPUs per job.** PCMM implements ModelManager's `simulationThreads` hook, reading
    `parallel/omp_num_threads` from each simulation's config through the variation record, and
    ModelManager passes that as `--cpus-per-task`. PhysiCell starts that many OpenMP threads
    whatever SLURM allocated, so without the hook every job would time-slice its threads on one
    CPU. A `cpus-per-task` you set yourself through [`setJobOptions`](@ref) replaces it and is
    never overridden.
