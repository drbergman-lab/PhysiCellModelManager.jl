# [Simulator interface](@id simulator_interface_dev)

The contract PhysiCellModelManager.jl fulfills for ModelManager: every hook, what ModelManager
expects from it, what PCMM does, and where the method is written.

ModelManager defines each hook as a generic function whose first argument is the active
[`AbstractSimulator`](@ref). PCMM `import`s the ones it implements at the top of
`src/simulator_interface.jl`, `src/configuration.jl`, `src/globals.jl` and `src/deletion.jl`, so its
methods extend ModelManager's function rather than shadowing it — an `import` line omitted is the
usual cause of a hook that is silently never called. Signatures and full docstrings are on the
Abstract Simulator Interface and PhysiCell Simulator reference pages; this page is the map between
them. The [Architecture](@ref architecture_dev) page has the call order these hooks fire in.

## Registration and identity

A simulator package's whole job at load time is to construct its backend and hand it over.

| Hook | ModelManager expects | PCMM |
|---|---|---|
| [`AbstractSimulator`](@ref) | The supertype. Its docstring lists the ten required methods. | Subtyped once, as [`PhysiCellSimulator`](@ref) — `src/physicell_simulator.jl`. |
| [`PhysiCellSimulator`](@ref) | — | Mutable struct holding the PhysiCell directory, compiler, current version ID, `march_flag`, and the Python, Studio, ImageMagick and FFmpeg paths. Everything ModelManager must stay ignorant of lives here. |
| [`registerSimulator!`](@ref ModelManager.registerSimulator!) | Called once in `__init__`; creates the [`ModelManagerGlobals`](@ref) around the backend. Idempotent for the same type, warns and replaces for a different one. | Called from `__init__` in `src/PhysiCellModelManager.jl` after reading `PHYSICELL_CPP` and the `PCMM_*` path variables from the environment. |
| [`simulator`](@ref) | Returns the active backend. | Not implemented — ModelManager's. PCMM calls it constantly; `simulator().dir`, `.compiler` and `.march_flag` are how the rest of the package reaches PhysiCell state. |
| [`simulatorDir`](@ref ModelManager.simulatorDir) | Required. The simulator's root directory; ModelManager runs simulation commands there. | Returns `physicellDir()`, i.e. `simulator().dir` — `src/simulator_interface.jl`. |
| [`simulatorInfo`](@ref ModelManager.simulatorInfo) | Required. A human-readable version string for banners and diagnostics. | Returns `physicellInfo()`, which describes the resolved PhysiCell repository owner, tag and commit — `src/simulator_interface.jl`, via `src/physicell_version.jl`. |
| [`postInitDisplay`](@ref) | Optional. Prints the initialization banner; the default prints the generic fields. | Prints the PCMM logo and version, then the PhysiCell directory, data directory, database path, `inputs.toml` path, PhysiCell version, compiler, HPC flag and parallelism — `src/simulator_interface.jl`. |

`PhysiCellSimulator`'s `march_flag` is the one field ModelManager knows nothing about and PCMM sets
late: `initializeModelManager` assigns it only after ModelManager's own init has probed for a
scheduler, `"x86-64"` on a cluster (where a cached executable runs on a machine that did not build
it) and `"native"` otherwise. The constructor cannot decide it, because the probe shells out and the
constructor runs inside every dependent package's precompilation.

## Database naming and schema

ModelManager owns the database; the backend supplies the names and the simulator-specific schema
fragments. These are pure functions of the backend — no state, no I/O — which is what lets
ModelManager build queries before a project is open.

| Hook | ModelManager expects | PCMM |
|---|---|---|
| [`centralDBFileName`](@ref) | The filename (not path) of the central SQLite database. | `"vct.db"` when a file of that name is already in the data directory, otherwise `"pcmm.db"` — `src/globals.jl`. |
| [`dbVersionTableName`](@ref ModelManager.dbVersionTableName) | The table that records the package version. | `"pcmm_version"` — `src/simulator_interface.jl`. |
| [`simulatorVersionTableName`](@ref ModelManager.simulatorVersionTableName) | The simulator version table. | `"physicell_versions"` — `src/simulator_interface.jl`. |
| [`simulatorVersionIDName`](@ref ModelManager.simulatorVersionIDName) | The foreign-key column that `simulations`, `monads` and `samplings` each carry, pointing at a row of the simulator version table above. | `"physicell_version_id"`, referencing `physicell_versions` — `src/simulator_interface.jl`. |
| [`simulatorVersionSchema`](@ref ModelManager.simulatorVersionSchema) | The SQL sub-schema for that table, used at database initialization. | `physicellVersionsSchema()` — `repo_owner`, `tag`, a `UNIQUE` `commit_hash`, and `date` — `src/database.jl`, dispatched from `src/simulator_interface.jl`. |
| [`resolveSimulatorVersionID`](@ref ModelManager.resolveSimulatorVersionID) | Resolve the version on disk against the table, inserting a row if it is new; return the ID. | `resolvePhysiCellVersionID()` in `src/physicell_version.jl`, dispatched from `src/simulator_interface.jl`. Re-run before every compile, because PhysiCell can be pulled or checked out mid-session. |
| [`currentSimulatorVersionID`](@ref ModelManager.currentSimulatorVersionID) | The row ID of the active version. | `currentPhysiCellVersionID()` — same two files. |
| [`tableIDName`](@ref) | Not a hook. The ID column for a table (`"configs"` → `"config_id"`). | Not implemented; call it rather than concatenating `_id` by hand. |

The `location*` family is the same idea for input locations, all derived from `inputs.toml` and all
ModelManager's. PCMM implements none of them, but everything it writes about input folders goes
through them instead of hard-coding a path:
[`locationFolder`](@ref) (the folder under `data/inputs/`), [`locationPath`](@ref) (its full path,
optionally joined with a folder or resolved for a sampling), [`locationTableName`](@ref) and
[`locationIDName`](@ref) / [`locationIDNames`](@ref) (the database table and its ID columns),
[`locationVariationsFolder`](@ref) (the variations subfolder), [`locationVariationsDBName`](@ref)
(the per-folder variations SQLite file), [`locationVariationsTableName`](@ref) (the table inside it),
and [`locationVariationIDName`](@ref) / [`locationVariationIDNames`](@ref) (the variation ID columns
on the trial tables).

Three generic entry points create and reset that database, none of them overridden here:
[`initializeDatabase`](@ref ModelManager.initializeDatabase) builds the schema if it is absent, [`reinitializeDatabase`](@ref ModelManager.reinitializeDatabase)
rescans `data/inputs/` to register folders added by hand (PCMM calls it at the end of
[`importProject`](@ref), `src/import.jl`), and [`resetFolder`](@ref ModelManager.resetFolder) drops one folder's variations
database and variations folder. [`calibrationsSchema`](@ref ModelManager.calibrationsSchema) is the schema for the `calibrations`
table; `src/up.jl` creates that table during the migration that introduced it, which is the one
place a simulator package touches a generic schema.

Two helpers exist for migrations and are used only from `src/up.jl`:
[`populateTableOnFeatureSubset`](@ref ModelManager.populateTableOnFeatureSubset) copies rows from an old table into a new one, matching columns
by name and renaming through an optional mapping — the standard move when a migration rebuilds a
table with a changed column set — and [`validateParsBytes`](@ref ModelManager.validateParsBytes) asserts that a variations table's
`par_key` blob still agrees with the float64 reinterpretation of its other columns, which is how a
migration that rewrites parameter columns proves it did not corrupt the keys.
[`orphanedTagCounts`](@ref) reports tag rows left pointing at deleted objects; it feeds
`databaseDiagnostics`, which the test suite asserts is warning-free after every suite.

## Input folders and variations

When a folder appears under `data/inputs/`, ModelManager registers it and then asks the backend what
else that folder needs. When a monad needs a varied input file, ModelManager writes the XML and then
asks the backend to fix it up.

| Hook | ModelManager expects | PCMM |
|---|---|---|
| [`insertFolder`](@ref) | Not a hook. Inserts the folder row, creates its variations database, then calls the two hooks below. | Called directly when PCMM creates a folder itself — `src/ic_cell.jl`, `src/ic_ecm.jl`, `src/components.jl`. |
| [`getInputFolderDescription`](@ref ModelManager.getInputFolderDescription) | Optional. A description for the new folder; default `""`. | Reads the `description` element of `metadata.xml` via `metadataDescription` — `src/simulator_interface.jl` and `src/database.jl`. |
| [`initializeInputFolder`](@ref ModelManager.initializeInputFolder) | Optional. Simulator-specific setup for a newly registered folder; default no-op. | Calls `prepareBaseFile` on it, so a folder is usable the moment it is registered — `src/simulator_interface.jl`. |
| [`prepareBaseFile`](@ref ModelManager.prepareBaseFile) | Optional. The path to the folder's base input file, or `nothing`. Default is `locationPath` joined with the basename. | Handles `:rulesets_collection` specially, generating `base_rulesets.xml` from the CSV when only the CSV is present; every other location falls through to the default — `src/configuration.jl`. |
| [`prepareVariedInputFolder`](@ref ModelManager.prepareVariedInputFolder) | Not a hook. Creates the variation XML for one location in a monad, if that location is varied. | Called from `setupMonad` for each varied location, and from `src/compilation.jl` where the config is needed before a build. |
| [`createXMLFile`](@ref ModelManager.createXMLFile) | Not a hook. Writes the variation XML at [`variationFilePath`](@ref ModelManager.variationFilePath) if it is not already there, returns the path, and then calls the hook below. | Called directly in `src/export.jl` to materialize the config and rules a user project export needs. |
| [`postVariationXMLProcessing`](@ref ModelManager.postVariationXMLProcessing) | Optional. Runs immediately after a variation XML is written; default no-op. | Splits embedded intracellular SBML out into its own files, so concurrent simulations sharing a variation do not race for the same document — `src/configuration.jl`. |

## Trial setup and launch

This is the hot path. ModelManager runs the loop and the concurrency; the backend contributes
compilation, varied input files, and one command line.

| Hook | ModelManager expects | PCMM |
|---|---|---|
| [`prepareTrialHierarchy`](@ref ModelManager.prepareTrialHierarchy) | Not a hook. Walks the trial, creates folders, calls the two setup hooks, and stops the walk if either returns `false`. Always runs before any command is built. | Not implemented. Its guarantee is what lets `simulationCommand` assume compilation and varied inputs are already done. |
| [`setupSampling`](@ref ModelManager.setupSampling) | Required. Once per sampling; returns `Bool`. | `loadCustomCode(S; force_recompile)` — compiles the custom code once for every monad sharing the same `InputFolders`. Takes `AbstractSampling`, so it works on a lone `Simulation` too — `src/simulator_interface.jl`. |
| [`setupMonad`](@ref ModelManager.setupMonad) | Required. Once per monad, after `setupSampling`; returns `Bool`. | Loops `projectLocations().varied` calling `prepareVariedInputFolder`; no compilation happens here. Returns `true` unconditionally — `src/simulator_interface.jl`. |
| [`SimulationSpec`](@ref ModelManager.SimulationSpec) | The unit of work: a `Simulation` plus its `monad_id`, handed to the runner. | Consumed, not produced. PCMM's `simulationCommand` reads `spec.simulation` only. |
| [`simulationCommand`](@ref ModelManager.simulationCommand) | Required. A bare `Cmd`, or `nothing` to record this simulation as failed and continue. No `pipeline`, no `env`. | `prepareSimulationCommand` builds `executable config_variation.xml` plus `-o` and whichever of `-i -s -e -d -r -n` this simulation's ICs, rules and intracellular inputs call for, with `dir=physicellDir()`. Returns `nothing` when IC cell or IC ECM setup throws, after writing the cause to the simulation's `output.err` — `src/simulator_interface.jl`. |
| [`simulationThreads`](@ref ModelManager.simulationThreads) | Optional. CPUs to request per SLURM job; default is no request. | `parallel/omp_num_threads` read through the variation record, so a varied thread count is honored. Falls back to 1 with one warning. PhysiCell calls `omp_set_num_threads` regardless of the allocation, so without this every job time-slices on one core — `src/simulator_interface.jl`. |
| [`runSimulation`](@ref ModelManager.runSimulation) | Optional. The default creates the output folder, redirects to `output.log` / `output.err`, runs in `simulatorDir` or submits with `sbatch`, and returns a `SimulationProcess`. | Not overridden — the default already describes how PhysiCell runs. |
| [`defaultJobOptions`](@ref ModelManager.defaultJobOptions) | Not a hook. Supplies `job-name` (`S<id>`) and `cpus-per-task` from `simulationThreads`; everything else is left to the site. | Not implemented. `simulationThreads` is PCMM's whole contribution to the SLURM script. |
| [`isRunningOnHPC`](@ref) | Not a hook. Probes for `sbatch` and sets `run_on_hpc`. | Not implemented, but read: PCMM's `initializeModelManager` uses the resulting `mm_globals().run_on_hpc` to choose `march_flag`. |
| [`postSimulationProcessing`](@ref ModelManager.postSimulationProcessing) | Optional. Non-destructive work after a simulation finishes and **before** the user's `post_processor`; default no-op. | Not implemented. Deliberately: PCMM's work here is destructive and belongs in the next hook. |
| [`postSimulationCleanup`](@ref ModelManager.postSimulationCleanup) | Optional. Destructive work, **after** the `post_processor`. Runs for every completed simulation, success or not. | Removes `output.err` and `hpc.err` on success; on failure rewrites `output.err` with the execution command above PhysiCell's stderr; then prunes the output folder per [`PruneOptions`](@ref). Early-returns on `isnothing(cmd)` — not on a `nothing` process, which is normal for a successful SLURM job — `src/simulator_interface.jl`. |
| [`clearSimulatorArtifacts`](@ref ModelManager.clearSimulatorArtifacts) | Optional. Remove simulator-built artifacts during a database reset; default no-op. | Deletes the build folder, `compilation.log`, `compilation.err` and `macros.txt` from every custom code folder. Nothing is matched by pattern, so a user's own file beside `main.cpp` is never at risk — `src/deletion.jl`. |

Two more names belong to machinery that runs *through* the same hooks rather than being hooks
themselves, and a backend implements neither. [`SimulationBank`](@ref ModelManager.SimulationBank) is the registry of existing
monads that ABC-SMC builds once per run so a later generation can reuse a simulation whose
parameters land in the same CDF cell; see [Calibration](@ref calibration_section_lib).
[`methodString`](@ref ModelManager.methodString) returns the lowercase identifier of a GSA method (`"moat"`, `"sobol"`) used to
name its result columns. Both sit above the simulator interface: a calibration or a sensitivity
analysis is a `Sampling`, so it reaches PhysiCell by the same path as any other trial.

!!! tierjournal "2026-04-24 — One dispatch axis: the simulator type"
    **Decided:** `runSimulation(::AbstractSimulator, spec)` does all simulator-specific routing, and
    [`SimulationSpec`](@ref ModelManager.SimulationSpec) — a `Simulation` plus its `monad_id` — is the concrete unit of work
    PCMM consumes as-is. Simulator flags such as `force_recompile` reach the hooks as keyword
    arguments through [`run`](@ref).
    **Rejected:** a second dispatch on the spec type. With one spec type per simulator it is
    redundant, and by the time a spec exists the simulator-specific routing is already done.

!!! tierjournal "2026-04-25 — `setupSampling` takes an `AbstractSampling`, `setupMonad` an `AbstractMonad`"
    **Decided:** the two setup hooks dispatch on the abstract type that states the invariant each
    needs, so a lone [`Simulation`](@ref) goes through the same path as a thousand-monad
    [`Sampling`](@ref). `setupSampling` always runs first and covers compilation, so `setupMonad`
    needs no flag asking whether to do the full setup, and a spec's `monad_id` is always an `Int`.

## Versioning and upgrades

The database records which version of PCMM wrote it. On every `initializeModelManager`, ModelManager
compares that with the loaded version and migrates if it is behind.

| Hook | ModelManager expects | PCMM |
|---|---|---|
| [`getInstalledVersion`](@ref) | The backend package's version as installed in the active environment. | Surfaced as `pcmmVersion()` — `src/pcmm_version.jl`. |
| [`getDBPackageVersion`](@ref) | The version recorded in the database under `dbVersionTableName`. | Surfaced as `pcmmDBVersion()`, which stamps the table with the current version if it does not exist yet — `src/pcmm_version.jl`. |
| [`resolvePackageVersion`](@ref) | Not a hook. Compares the two and drives the migration; returns `false` if the database is ahead of the code or a migration failed. | Not implemented. Note it targets the *loaded* version, not the installed one, so a migration matches the code actually executing. |
| [`upgradeMilestones`](@ref ModelManager.upgradeMilestones) | A **sorted** vector of versions that have schema changes. | `pcmm_milestones` in `src/up.jl` — the list of thirteen versions from `v"0.0.1"` on. |
| [`upgradeToMilestone`](@ref ModelManager.upgradeToMilestone) | Apply the migration for one version; called in order for every milestone between the recorded and loaded versions. | Looks the version up in `upgrade_fns` and asserts a function is registered — `src/simulator_interface.jl`, with the functions themselves in `src/up.jl`. |
| [`continueMilestoneUpgrade`](@ref ModelManager.continueMilestoneUpgrade) | Not a hook. Warns about the schema change and prompts unless `auto_upgrade` is set; returns whether to proceed. | Called at the top of each migration function in `src/up.jl`, which returns early if it says no. |

Adding a milestone means three edits in `src/up.jl` — the version into `pcmm_milestones`, a function
registered in `upgrade_fns`, and a matching change to the schema in `src/database.jl` so new
projects are created correctly. A milestone with no migration, or a schema change with no milestone,
leaves one of the two populations of projects broken.

!!! tierjournal "2026-06-15 — Upgrade CI generates old projects and upgrades them forwards"
    **Decided:** the upgrade job generates a project with an older *released* PCMM and then opens it
    with the dev checkout, so CI exercises the `src/up.jl` in the repository rather than a released
    copy of it. Verification reads the SQLite file directly.
    **Rejected:** a `target_version` cap on [`initializeModelManager`](@ref), which would let CI stop
    part-way; `upgradePackage` always migrates to the running version, and capping it is a
    ModelManager change.
    **Open:** how far back the generating API can be reused for still older projects.
