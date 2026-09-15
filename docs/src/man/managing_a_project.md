# [Managing a project](@id managing_a_project_man)

Everything that happens to a project as a whole: opening it, throwing away runs you no longer
want, starting over, and moving an old project onto a new release.

## Open a project

!!! tierwhy
    `using PhysiCellModelManager` tries `initializeModelManager()` on the working directory, so a
    script launched from the project root needs no explicit call. It is not an error when there is
    no project there — you get an informational message pointing at `createProject` and
    `initializeModelManager` — so the package still loads in a session that is about to create
    one. Call [`initializeModelManager`](@ref) explicitly whenever the project is somewhere other
    than `pwd()`, which includes most job scripts.

!!! tiergloss
    [`createProject`](@ref) builds a new project folder — `data/`, `PhysiCell/`, and `scripts/`.
    [`initializeModelManager`](@ref) attaches the current Julia session to an existing one, either
    from a project directory holding both `PhysiCell/` and `data/`, or from the two paths
    separately.

```julia
using PhysiCellModelManager   # auto-attaches if PhysiCell/ and data/ are in the working directory

createProject("my-project")
initializeModelManager("my-project")
initializeModelManager("path/to/PhysiCell", "path/to/data")
```

!!! tierdev
    **Where am I, and am I attached?** [`dataDir`](@ref) returns the attached project's `data/`
    path and [`isInitialized`](@ref) reports whether attaching succeeded. `initializeModelManager`
    throws `PCMMMissingProject` when the two directories are not where it looked, and returns
    `false` for the failures ModelManager reports, so `isInitialized()` is the thing to test.

## Delete runs

!!! tierwhy
    Two keywords control the cascade in opposite directions. `delete_subs` decides whether the
    contents go too — deleting a monad without it leaves its simulations on disk, now belonging to
    nothing. `delete_supers` (true by default for [`deleteSimulations`](@ref)) decides whether a
    container left empty by the deletion is removed as well, which is what keeps a pruned sweep
    from leaving a shell of empty monads behind. `filters` adds SQL `WHERE` conditions, so a range
    can be narrowed by any column the simulations table carries.

!!! tiergloss
    [`deleteSimulations`](@ref) (alias [`deleteSimulation`](@ref)) removes simulations from the
    database, from disk, and from the post-processing sink. [`deleteMonad`](@ref),
    [`deleteSampling`](@ref), and [`deleteTrial`](@ref) work one level at a time.
    [`deleteAllSimulations`](@ref) empties the lot, and [`deleteSimulationsByStatus`](@ref)
    filters by how each run ended.

```julia
deleteSimulations(1:3)
deleteSimulations(1:100; filters = Dict("config_id" => 1))

deleteMonad(4:6; delete_subs = true)          # also delete their simulations
deleteSampling(2; delete_supers = false)      # leave an emptied trial in place
deleteTrial(1; delete_subs = true)

deleteSimulationsByStatus("Failed")                       # prompts first
deleteSimulationsByStatus(["Queued", "Failed"]; user_check = false)
deleteAllSimulations()
```

!!! tierdev
    The status strings [`deleteSimulationsByStatus`](@ref) accepts are exactly what
    [`recognizedStatusCodes`](@ref ModelManager.recognizedStatusCodes) returns: `"Not Started"`, `"Queued"`, `"Running"`,
    `"Completed"`, `"Failed"`.

## Start over

!!! tierwhy
    On a shared filesystem some of what this removes may be staged in `data/.trash/` instead of
    deleted outright, and that space is not reclaimed until a later session manages to retry it.
    A reset on a cluster can therefore leave the quota unchanged for a while; that is expected,
    not a failed reset.

!!! tiergloss
    [`resetDatabase`](@ref) deletes every output folder, removes the post-processing sink
    (`data/outputs/postprocessing.db`), clears the variation files, drops the simulator's build
    artifacts, and rebuilds an empty database. The `data/inputs/` folders are untouched. It asks
    for confirmation before doing any of it.

```julia
resetDatabase()                      # prompts
resetDatabase(; force_reset = true)  # no prompt; for scripts that mean it
```

## Move an old project onto a new release

!!! tiergloss
    When a release changes the database schema, opening an old project warns, links to
    [Database upgrades](@ref database_upgrades_misc), and waits for you to approve the migration.
    Pass `auto_upgrade = true` to approve it up front, which is what a batch job needs.

```julia
initializeModelManager("my-project"; auto_upgrade = true)
```

!!! tierdev
    [`upgradePackage`](@ref ModelManager.upgradePackage) is the function behind that prompt. It walks the milestone versions
    between the project's recorded version and the loaded one, stamping the version table after
    each milestone so an interrupted upgrade resumes rather than restarts, and aborting the chain
    on the first milestone that fails. A target beyond the version loaded in the session is
    refused outright.

## Health checks

!!! tierdev
    [`initializeModelManager`](@ref) launches [`databaseDiagnostics`](@ref ModelManager.databaseDiagnostics) in a background task:
    it compares the database against the output folders, reports orphaned entries and broken
    constituent IDs, and recovers simulations a killed session left stuck at `Running` or
    `Queued`. That recovery is the one thing it writes — without it those rows stay started
    forever and every later run skips them while reporting that it saved you time. Interactively
    the task finishes in the first idle moment; in a short script call
    [`waitForDiagnostics`](@ref) to block until it has printed.

```julia
initializeModelManager("my-project")
waitForDiagnostics()
databaseDiagnostics()   # or run the checks again by hand at any time
```

## Renamed and deprecated names

!!! tierdev
    Older scripts may use names that still work but are no longer the ones to write:

    - `PCMMOutput` → [`MMOutput`](@ref), the result type [`run`](@ref) returns.
    - `SobolPCMM` → [`SobolMM`](@ref), the Sobol' sequence variation method.
    - `getCellDataSequence` → [`cellDataSequence`](@ref).

    Each old name is a plain alias, so nothing breaks; the new names came with the move of the
    generic machinery into ModelManager, which the `MM` spelling reflects.
