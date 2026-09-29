# [Architecture](@id architecture_dev)

Where to make a change: what the two packages own, what lives in each file, and what a call does
between `createTrial` and a finished simulation.

## The split

PhysiCellModelManager.jl is one of two packages. ModelManager.jl owns everything that is not about
PhysiCell: the trial hierarchy ([`Simulation`](@ref), [`Monad`](@ref), [`Sampling`](@ref),
[`Trial`](@ref)) and its central SQLite database, the runner that launches simulations locally or as
SLURM jobs, the variation machinery ([`DiscreteVariation`](@ref), [`CoVariation`](@ref),
[`LatentVariation`](@ref) and the sampling methods behind them), tags and recovery, global
sensitivity analysis, and calibration. PCMM is the PhysiCell backend for that infrastructure — it
implements the [`AbstractSimulator`](@ref) contract as [`PhysiCellSimulator`](@ref), knows how
PhysiCell's XML inputs are shaped and how its custom code is compiled, and adds the analysis that
only makes sense for PhysiCell output (cell populations, substrates, motility, pair correlation
functions, graphs, movies, Studio). PCMM re-exports ModelManager wholesale with `@reexport`, so a
user types `using PhysiCellModelManager` and never sees the seam. A name you cannot find in `src/`
is almost certainly ModelManager's; look for it there before adding it here.

The practical rule for "where does my change go": if it would be true of a simulator that is not
PhysiCell, it belongs in ModelManager. If it mentions a PhysiCell config XML, a `-march` flag, a
`main.cpp`, or an output `.mat` file, it belongs here.

## Module map

Every file under `src/`. The module entrypoint `src/PhysiCellModelManager.jl` fixes the include
order; a new file must be added there.

| File | What lives there |
|---|---|
| `src/PhysiCellModelManager.jl` | Module entrypoint. Re-exports ModelManager, sets the include order, and in `__init__` constructs a [`PhysiCellSimulator`](@ref) from the `PHYSICELL_CPP` / `PCMM_*` environment variables, registers it, and auto-initializes a project found in `pwd()`. Also PCMM's `initializeModelManager` methods, which resolve the PhysiCell and data directories and set `march_flag`. |
| `src/exceptions.jl` | [`PCMMException`](@ref PhysiCellModelManager.PCMMException) and its concrete subtypes. |
| `src/physicell_simulator.jl` | The [`PhysiCellSimulator`](@ref) struct and its default constructor. All its fields are PhysiCell state that ModelManager must not know about. |
| `src/utilities.jl` | [`quietRun`](@ref ModelManager.quietRun). |
| `src/globals.jl` | `centralDBFileName(::PhysiCellSimulator)` (the `vct.db` / `pcmm.db` choice) and `physicellDir()`. |
| `src/pruner.jl` | [`PruneOptions`](@ref) and the deletion of simulation output files after a run. |
| `src/variations.jl` | PhysiCell variation infrastructure: `inferVariationLocation`, which maps an [`XMLPath`](@ref) to the input location that owns it, the constructors that take no location, and [`domainVariations`](@ref). |
| `src/compilation.jl` | `loadCustomCode` and everything around it: compiler flags and macros, the executable naming keyed to the PhysiCell version, the build folder, and the temporary-copy compile that lets several samplings compile at once. |
| `src/configuration.jl` | PhysiCell XML: the path helpers ([`configPath`](@ref), [`rulePath`](@ref), [`icCellsPath`](@ref), [`icECMPath`](@ref)), reading and writing config elements, and PCMM's `prepareBaseFile` and `postVariationXMLProcessing` methods. The largest file in the package. |
| `src/creation.jl` | [`createProject`](@ref): the `data/` tree, the `inputs.toml` template, and downloading a PhysiCell release. |
| `src/database.jl` | Only what is PhysiCell-specific: `physicellVersionsSchema`, `metadataDescription`, and the `getParameterValue` methods that infer a location from an [`XMLPath`](@ref). Generic database code is ModelManager's. |
| `src/deletion.jl` | `clearSimulatorArtifacts(::PhysiCellSimulator)` — what a database reset removes from the custom code folders. |
| `src/ic_cell.jl` | IC cell templates and the per-simulation IC cell CSV generated from them. |
| `src/ic_ecm.jl` | The same for IC ECM. |
| `src/simulator_interface.jl` | The bulk of the [Simulator interface](@ref simulator_interface_dev): most `PhysiCellSimulator` methods on ModelManager hooks, plus `prepareSimulationCommand`, which assembles the PhysiCell command line. |
| `src/up.jl` | Database migrations. `pcmm_milestones` lists every version with a schema change; `upgrade_fns` maps each to its migration. |
| `src/pcmm_version.jl` | `pcmmVersion` and `pcmmDBVersion`. |
| `src/physicell_version.jl` | Resolving the PhysiCell version from the repository on disk, recording it in `physicell_versions`, and `refreshPhysiCellVersion` / `physicellInfo`. |
| `src/components.jl` | [`PhysiCellComponent`](@ref) and [`assembleIntracellular!`](@ref): reusable intracellular model pieces. |
| `src/loader.jl` | Database identity on top of PhysiCellOutput.jl — `simulation_id`- and `Simulation`-keyed entry points that resolve to an output folder and then delegate. |
| `src/import.jl`, `src/import_classes.jl` | [`importProject`](@ref) and the `ImportSource` / `CopyOrMove` descriptors that say what is copied or moved from a PhysiCell user project. |
| `src/movie.jl` | [`makeMovie`](@ref), via ImageMagick and FFmpeg. |
| `src/physicell_studio.jl` | [`runStudio`](@ref): temporary config and rules files, then the Python launch. |
| `src/export.jl` | [`exportSimulation`](@ref): a simulation written back out as a PhysiCell `user_project`. |
| `src/analysis/analysis.jl` | Include list only. |
| `src/analysis/preprocessing.jl` | Shared argument handling for the analysis functions (cell-type inclusion lists and the like). |
| `src/analysis/population.jl` | [`populationCount`](@ref), [`populationTimeSeries`](@ref), [`finalPopulationCount`](@ref) and their plot recipes. |
| `src/analysis/substrate.jl` | Substrate concentration statistics, voxel weighting, and averages over cells. |
| `src/analysis/motility.jl` | [`motilityStatistics`](@ref): per-cell distance, time and speed, split by the cell types a cell passed through. |
| `src/analysis/pcf.jl` | Pair correlation functions over a snapshot or a simulation, and `PCMMPCFResult`. |
| `src/analysis/graphs.jl` | [`connectedComponents`](@ref) over PhysiCell's neighbor, attachment and spring graphs. |
| `src/analysis/runtime.jl` | [`simulationRuntime`](@ref). |
| `src/analysis/standard_qois.jl` | Ready-made [`QoI`](@ref) builders: [`populationCountQoI`](@ref), [`populationFractionQoI`](@ref), [`meanPopulationTimeSeriesQoI`](@ref). |

## From createTrial to a finished simulation

One call, start to finish. Everything named as a hook is defined in ModelManager and implemented
for PhysiCell in this package; the [Simulator interface](@ref simulator_interface_dev) page gives
the contract for each.

```julia
run(createTrial(inputs, variations; n_replicates=3))

# `run` also takes createTrial's own arguments and does both steps itself:
run(inputs, variations; n_replicates=3)
```

The second form is the one most scripts use; it calls `createTrial` with exactly those arguments and
then runs what comes back, so everything below applies unchanged to both.

1. **`createTrial`** is entirely ModelManager's. It expands `variations` according to the
   [`AddVariationMethod`](@ref ModelManager.AddVariationMethod) it was given (default `GridVariation()`), writes one row per
   distinct parameter set into each location's per-folder variations database, and builds the
   [`Simulation`](@ref), [`Monad`](@ref) or [`Sampling`](@ref) that holds them. PCMM contributes one
   thing here: `inferVariationLocation` in `src/variations.jl`, which is how a bare `XMLPath` from
   [`configPath`](@ref) or [`rulePath`](@ref) knows it means `:config` or `:rulesets_collection`.

2. **`run`** first calls `prepareTrialHierarchy`, which walks the hierarchy creating trial folders
   and calling two hooks. [`setupSampling`](@ref ModelManager.setupSampling) runs once per sampling; PCMM compiles the custom
   code there (`loadCustomCode`), so a sampling of a thousand monads compiles once. Then
   [`setupMonad`](@ref ModelManager.setupMonad) runs per monad; PCMM loops over `projectLocations().varied` calling
   [`prepareVariedInputFolder`](@ref ModelManager.prepareVariedInputFolder), which goes through [`createXMLFile`](@ref ModelManager.createXMLFile) to
   [`variationFilePath`](@ref ModelManager.variationFilePath) and then [`postVariationXMLProcessing`](@ref ModelManager.postVariationXMLProcessing) — PCMM's method there
   splits embedded SBML out of intracellular XML so concurrent simulations do not race for it.

3. **Launch.** ModelManager collects the pending simulations as [`SimulationSpec`](@ref ModelManager.SimulationSpec)s and wraps
   each in a task calling [`runSimulation`](@ref ModelManager.runSimulation). PCMM does not override `runSimulation`; the
   default asks [`simulationCommand`](@ref ModelManager.simulationCommand), and PCMM's method calls `prepareSimulationCommand`
   (`src/simulator_interface.jl`), which creates the `output/` subfolder and assembles the
   executable, the config variation XML, and the `-i`, `-s`, `-e`, `-d`, `-r`, `-n` flags for
   whichever IC, rules and intracellular inputs this simulation uses. ModelManager runs that command
   in [`simulatorDir`](@ref ModelManager.simulatorDir), or submits it with `sbatch` when `run_on_hpc` is set — in which case
   [`defaultJobOptions`](@ref ModelManager.defaultJobOptions) asks [`simulationThreads`](@ref ModelManager.simulationThreads) how many CPUs to request, and PCMM
   answers with `parallel/omp_num_threads` read from the simulation's own variation record.

4. **After each simulation.** ModelManager calls [`postSimulationProcessing`](@ref ModelManager.postSimulationProcessing) (PCMM leaves the
   no-op default), then the user's `post_processor` if one was passed, then
   [`postSimulationCleanup`](@ref ModelManager.postSimulationCleanup). PCMM's cleanup is where the destructive work happens: remove
   `output.err` on success, annotate it with the command on failure, and prune the output folder
   according to [`PruneOptions`](@ref). The ordering is the contract — a `post_processor` must see
   the output folder intact.

5. ModelManager updates each simulation's status in the database and returns an [`MMOutput`](@ref).

!!! tierjournal "2026-07-07 — All of PCMM's per-simulation work is cleanup, after the callback"
    **Decided:** the whole body moved into [`postSimulationCleanup`](@ref ModelManager.postSimulationCleanup) — pruning *and* the
    `output.err` handling — leaving [`postSimulationProcessing`](@ref ModelManager.postSimulationProcessing) at ModelManager's no-op
    default. A user's `post_processor` therefore always sees the intact output folder.
    **Rejected:** moving only the pruning. The error-file handling reads the same after the callback
    as before it, and splitting one body across two hooks buys nothing.

## Type hierarchy

The trial types form one chain, narrowing by what the members share:

- [`AbstractTrial`](@ref) — anything runnable.
  - [`AbstractSampling`](@ref) — all member simulations share the same [`InputFolders`](@ref); only
    variations differ.
    - [`AbstractMonad`](@ref) — all member simulations share input folders *and* variation IDs, so
      they differ only in random seed.
      - [`Simulation`](@ref) — one run.
      - [`Monad`](@ref) — replicates of one parameter set.
    - [`Sampling`](@ref) — monads over one set of input folders.
  - [`Trial`](@ref) — samplings that may use different input folders.

Dispatch on the abstract type that states the invariant you need: `setupSampling` takes an
`AbstractSampling` because compilation depends only on the input folders, and `setupMonad` takes an
`AbstractMonad` because varied input files depend on the variation IDs.

Four more abstract types are the extension points elsewhere. [`AbstractVariation`](@ref) is the
supertype of `ElementaryVariation`, [`DiscreteVariation`](@ref), [`DistributedVariation`](@ref) and
[`CoVariation`](@ref) — the things `createTrial` expands. [`AddVariationMethod`](@ref ModelManager.AddVariationMethod) is how that
expansion is sampled ([`GridVariation`](@ref), [`LHSVariation`](@ref), [`SobolVariation`](@ref),
[`RBDVariation`](@ref)). [`GSAMethod`](@ref ModelManager.GSAMethod) is a global sensitivity analysis ([`MOAT`](@ref),
[`Sobolʼ`](@ref), [`RBD`](@ref)). [`AbstractCalibrationMethod`](@ref) is a calibration algorithm,
currently [`ABCSMC`](@ref). All four are ModelManager's and none is subtyped in PCMM.

The fifth is the one PCMM exists to implement: [`AbstractSimulator`](@ref), whose single concrete
subtype here is [`PhysiCellSimulator`](@ref).

## Globals and project state

ModelManager holds one mutable [`ModelManagerGlobals`](@ref) per process, reached with
[`mm_globals`](@ref). It carries the data directory, the active simulator, the database connection,
the parsed `inputs.toml`, the HPC flags and `sbatch` options, the parallelism limit, and the
provenance and session identifiers stamped onto everything `createTrial` and `run` create. Any
function that reads project state should call [`assertInitialized`](@ref) first, which throws a
message telling the user to run `initializeModelManager`; `isInitialized` answers the same question
without throwing.

The input side of that state comes from `inputs.toml`, at [`pathToInputsConfig`](@ref), parsed by
[`parseProjectInputsConfigurationFile`](@ref) into [`inputsDict`](@ref) and a
[`ProjectLocations`](@ref) available as [`projectLocations`](@ref). `ProjectLocations` is three
tuples of location symbols — `all`, `required`, `varied` — and iterating one of them is how PCMM
avoids hard-coding the list of PhysiCell inputs; `setupMonad` loops over `.varied`, and
[`folderIsVaried`](@ref) answers the same question for one folder. A single folder in use is an
[`InputFolder`](@ref) (location, database ID, folder name, basename, required, varied, path from
`data/inputs/`), and its description comes from [`getInputFolderDescription`](@ref ModelManager.getInputFolderDescription), which PCMM
implements by reading `metadata.xml`.

Variations are addressed by [`VariationID`](@ref), which records one row ID per varied location:
`-1` for a location not in use, `0` for the base file, and a positive integer for a row in that
location's variations database. [`variationFilePath`](@ref ModelManager.variationFilePath) turns a location and a monad into the
path of the XML file for that ID, whether or not it exists yet — derive paths through it rather than
rebuilding the naming convention. [`shortLocationVariationID`](@ref) gives the abbreviated column
name a location's variation ID gets in printed tables (`:ConfigVarID`, `:RulesVarID`, and so on);
PCMM's method in `src/simulator_interface.jl` is the list of those abbreviations.

## Errors

PCMM raises [`PCMMException`](@ref PhysiCellModelManager.PCMMException) subtypes rather than bare `ErrorException`s, so a caller — Model
Manager Studio in particular, which drives PCMM programmatically — can branch on what went wrong
instead of parsing a message. The hierarchy is in `src/exceptions.jl`:

- [`PCMMMissingProject`](@ref PhysiCellModelManager.PCMMMissingProject) — no PhysiCell and data directory pair at the given or inferred
  paths. Raised by `initializeModelManager`; the auto-initialization in `__init__` catches exactly
  this one and prints guidance rather than failing the `using`.
- [`PCMMStudioLaunchError`](@ref PhysiCellModelManager.PCMMStudioLaunchError) — Studio could not be launched or exited non-zero. Carries the
  `Cmd` and the underlying `cause`, which is a `Base.IOError` when Python itself could not be
  spawned and a `ProcessFailedException` when Studio ran and failed.

A new failure mode that a caller might reasonably want to distinguish gets a new subtype here, with
fields carrying the identifiers needed to act on it, and a `Base.showerror` method.

## Invariants

Things that are true of the code as it stands, and break something concrete if they stop being true.

- **A database change touches both `src/database.jl` and `src/up.jl`.** The schema is created once
  for a new project and migrated for every existing one. A schema change with no migration leaves
  every project on disk unopenable at the new version; a migration with no schema change leaves new
  projects missing the column. Add the version to `pcmm_milestones` and a function to `upgrade_fns`.
- **The compiled executable is named for the PhysiCell version it was built against**, and lives in
  the custom code folder's build folder. Its presence there *is* the record that a build finished:
  nothing is written before `make` succeeds, and a failed compile deletes the executable it was
  replacing. Anything that writes a build marker earlier makes a failed compile look finished on the
  next run.
- **The PhysiCell version is re-resolved before every compile decision**, because a user can pull or
  check out PhysiCell mid-session. A dirty or downloaded PhysiCell forces a recompile, since the
  recorded version is then not a trustworthy cache key.
- **One backend per process.** `registerSimulator!` warns and replaces the globals if a different
  simulator type registers, and PCMM's `_pcmmGlobalsRegistered` keys on the simulator type for
  exactly that reason. Code may assume `simulator()` is a `PhysiCellSimulator`.
- **`postSimulationCleanup` is the only destructive per-simulation hook**, and it runs after the
  user's `post_processor`. Moving destructive work earlier means a callback sees a pruned folder.
- **A simulation command is a bare `Cmd` with no environment.** ModelManager refuses a `pipeline` or
  a `Cmd` carrying `env`, because a `Cmd.env` replaces the environment locally and is not forwarded
  at all through `sbatch --wrap` — the same command would mean two things. Put what PhysiCell needs
  in the arguments or the working directory.
- **`__init__` does no work with effects outside the process while output is being generated.**
  It runs in the precompilation subprocess of every dependent package; `_generatingOutput()` gates
  everything past simulator registration, which is why auto-initialization and any shelling out come
  after that check.

!!! tierjournal "2026-08-19 — The executable's name is the build record"
    **Decided:** the compiled binary is `project_<physicell-version>` in a `pcmm_build/` folder PCMM
    owns, and its existence is the only record that a build for that version finished. `macros.txt`
    is written only after `make` succeeds, an abandoned build deletes the executable it was
    replacing, and old executables are kept so switching PhysiCell versions back and forth costs no
    rebuild.
    **Rejected:** a separate marker file written before `make`, which let a failed compile leave a
    stale binary beside a file claiming the new version.

## Running the tests and the docs build

The full suite, from the repository root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

`test/runtests.jl` deletes the previous run's artifacts (`test/data`, `test/PhysiCell`, and the
handful of generated project and export folders beside them) at the **start**, so they survive a run
for inspection, then includes each file of
`test_order` in turn with `databaseDiagnostics()` asserted after each. `test_order` is a sequence,
not a set: `CreateProjectTests.jl` builds the project every later suite runs against. A new test
file is added to `test_order`, and any new output path it creates is added to both `test/.gitignore`
and the cleanup list at the top of `runtests.jl`.

One suite, run against the project an earlier full run left behind — from `test/`, so that
`using PhysiCellModelManager` auto-initializes it:

```bash
julia --project=. -e 'cd("test"); using PhysiCellModelManager, Test; include("test-scripts/PrintHelpers.jl"); include("test-scripts/DatabaseTests.jl")'
```

Suites that need a compiled PhysiCell binary fail locally without one; they pass on the GitHub
runners, where it is downloaded.

The docs:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

`docs/make.jl` regenerates `docs/src/dev/journal.md` from every `!!! tierjournal` block under
`docs/src` before calling `makedocs`; commit the regenerated file. It runs with
`checkdocs=:exports`, and `docs/src/lib/*.md` renders only the public API — so a docstring that
`@ref`s a non-public binding fails the build. `test/test-scripts/DocstringRefTests.jl` catches that
in the ordinary suite, with no docs build needed.
