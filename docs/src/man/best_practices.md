# [Best practices](@id best_practices_man)

Habits that keep a PhysiCellModelManager.jl project reproducible; the headings alone are the
summary.

## [Do NOT manually edit files inside `inputs`](@id no_manual_input_edits)

!!! tiergloss
    To change a parameter value, use a variation — see [Varying parameters](@ref
    varying_parameters_man) and `scripts/GenerateData.jl`. To change the *structure* of an input
    file, such as adding a rule or editing custom code, create a new subdirectory within the
    relevant `inputs` subdirectory rather than editing the one in use.

!!! tierwhy
    PhysiCellModelManager.jl owns the databases that map input folders and variation IDs to the
    simulations that ran with them. An edit in place makes every past simulation's recorded
    parameterization a lie, with nothing to detect it. If you expect to do a lot of structural
    editing, consider using PhysiCell Studio for your first round of model development and
    refinement.
    <!-- PhysiCellModelDeveloper.jl could be made to address this though... -->

## Suggested practices

### [Use `createProject` to create a new PCMM project](@id use_create_project)

!!! tiergloss
    [`createProject`](@ref) creates a new PCMM project directory with the structure and files PCMM
    expects — a distinct thing from a PhysiCell sample project or user project. Pass
    `template_as_default=false` to skip copying the template PhysiCell project.

```julia-repl
createProject("MyNewProject"; template_as_default=false)
```

### Be slow to delete simulations and scripts

!!! tiergloss
    Delete simulations with [`deleteSimulations`](@ref) rather than by hand, so the database stays
    consistent — for instance after an error has left a stale record.

!!! tierwhy
    PhysiCellModelManager.jl tracks simulations in a database and skips re-running ones that already
    exist, so adding simulations to a script and re-running it — including on an HPC — runs only the
    new ones. A script is therefore also a record you can use to reproduce results later.

### On a cluster, set the job's resources and keep the driver alive

!!! tiergloss
    Set `time` and `mem` with [`setJobOptions`](@ref) before the first `run`. The CPU count is not
    yours to set: ModelManager asks SLURM for as many CPUs per job as the simulation's
    `omp_num_threads` (PCMM reports it through `simulationThreads`), so it already matches the
    config file. Run long campaigns from `tmux`, `nohup`, or a batch job that outlives them.

!!! tierwhy
    A job the scheduler kills for exceeding an unset default is only noticed minutes later. And the
    Julia session that called `run` is what records each job's outcome, so if it dies the runs
    finish with nothing written down. The
    [ModelManager HPC manual](https://drbergman-lab.github.io/ModelManager.jl/stable/man/hpc/)
    covers submit limits, refused submissions, interrupting a run, and finding a job in `sacct`.

### Use a dedicated Julia environment

!!! tiergloss
    Keep each project's dependencies in its own environment and commit `Project.toml` and
    `Manifest.toml`. See [Julia environments](@ref julia_environments_man).

### [Use version control on `inputs` and `scripts` directories](@id version_control_inputs)

!!! tiergloss
    Those two directories plus the PhysiCell version are enough to reproduce a project.
    [`createProject`](@ref) adds a `.gitignore` in the data directory so the right files are tracked.

### Update PhysiCell between campaigns, not during one

!!! tiergloss
    PhysiCell lives at `PhysiCell/` inside the project, so updating it is a git operation. If you
    added PhysiCell as a submodule, run `git submodule update --remote PhysiCell` from the project
    root instead.

```bash
git -C PhysiCell fetch --tags
git -C PhysiCell checkout <tag-or-commit>
```

!!! tierwhy
    PhysiCellModelManager.jl re-reads the PhysiCell version before every compilation, so you do not
    need to restart Julia: the next `run` recompiles, and since the executable is named for the new
    version, switching back to a version you have already built does not rebuild. That check happens
    once per sampling, though, so a single `Trial` spanning several samplings can straddle two
    PhysiCell versions — finish a campaign before updating.

### Keep the PhysiCell working tree clean

!!! tiergloss
    Commit changes under `PhysiCell/` (or stash them) before running.

!!! tierwhy
    Uncommitted changes cannot be pinned to a commit, so the version is recorded with a `-dirty`
    suffix and the custom code is recompiled on every run. A real commit hash is reproducible, and
    its build is cached like every other version.
