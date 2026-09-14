# Product Requirements Document — PhysiCellModelManager.jl (PCMM)

> **Purpose:** This document defines the complete feature set of PCMM in behavioral terms. It is the authoritative answer to "what should this system do?" Read this at the start of any feature session to establish alignment between intent and implementation plan.

---

## Product Overview

**Vision:** PCMM eliminates manual file I/O and workflow overhead in PhysiCell agent-based modeling studies. It manages simulation runs and their provenance in a structured database, enabling reproducible parameter exploration, sensitivity analysis, and calibration with minimal boilerplate.

**Target Framework:** PhysiCell only. Generalization to other ABM frameworks is explicitly deferred to v2.

---

## Feature: Project Initialization

**One-line description:** Create and configure a PCMM project in a user-chosen directory.

**Behavioral specification:**
- `createProject(path)` initializes a PCMM project folder with the canonical subdirectory layout and an SQLite database.
- `initializeModelManager(path)` connects an existing PCMM project to the current Julia session; sets module-level globals.
- After initialization, all subsequent PCMM calls operate relative to that project root.
- `using PhysiCellModelManager` registers the module globals and then auto-initializes from the working directory. Whenever that succeeds — and therefore whenever the globals change — the initialization banner is printed.
- Loading the package does **not** auto-initialize while Julia is generating a precompilation cache file or a system image.

**Acceptance criteria:**
- A fresh directory becomes a valid project after one `createProject` call.
- Re-initializing an already-initialized project does not corrupt the database.
- `databaseDiagnostics()` passes with no errors after initialization.
- A redundant `__init__` in a process that already initialized a PCMM project is a no-op: the existing globals object and database handle are kept, not rebuilt.
- Precompiling a package that depends on PCMM emits no banner and touches no project database.

**Edge cases:**
- Path does not exist → create it.
- Path already contains a PCMM database → re-attach, do not reinitialize.
- Called without any path → use current working directory.
- Another ModelManager backend already owns `mm_globals_ref` → PCMM claims it and registers its own `PhysiCellSimulator`, rather than deferring and then running against a foreign simulator. (`ModelManagerGlobals` holds exactly one `simulator`, so the two backends cannot coexist in one process; the last one loaded wins.)
- Loaded inside a precompilation subprocess → globals are registered (cheap, in-process) but no project is initialized, so `mm_globals()` still works for any downstream precompilation workload.
- An **unselected** (`""`) optional input folder → `prepareBaseFile` returns `nothing`, for every location including `:rulesets_collection`. Nothing is generated and no error is raised, because there is no folder to prepare.
- A **selected** `:rulesets_collection` folder containing neither `base_rulesets.csv` nor `base_rulesets.xml` is rejected by `InputFolder` construction, before `prepareBaseFile` runs. PCMM adds no second check for it.

---

## Feature: Model Import

**One-line description:** Import a PhysiCell project folder into PCMM's input management system.

**User story:** As a researcher, I want to import a PhysiCell project so that I can use PCMM tooling for parameter sweeps, analysis, and calibration without managing file I/O or simulation bookkeeping manually.

**Behavioral specification:**
- `importProject(path)` copies config, custom modules, rulesets, and IC files into PCMM's versioned `inputs/` tree.
- Returns the folder names assigned to each input type (config, custom code, rules, IC cell, IC ECM).
- `InputFolders` struct ties those names together for use in downstream calls.

**Acceptance criteria:**
- After import, the copied files are reachable through `InputFolders`.
- Import is idempotent: re-importing the same folder produces the same folder name.

**Edge cases:**
- Missing optional input types (rules, IC files) → omit from `InputFolders` gracefully.
- Source folder has no XML config → error with descriptive message.

---

## Feature: Model Import Wizard

**One-line description:** Support the model import process with an interactive GUI that guides users through selecting input folders and validating their contents.

**Behavioral specification:**
- update `importProject(path)` to launch a GUI; use `importProject(path; interactive=false)` to retain CLI behavior.
- GUI prompts user to select folders all available input types in a table of `| Input Type | File Path | Browse Button | Destination | Status |` rows.
- For each input type, user clicks "Browse" to select the corresponding folder; PCMM validates the selection (e.g., config folder must contain an XML file).
  - Destination column shows the assigned folder name in `inputs/` after successful validation.
    - This defaults to the name of the subdirectory of `user_projects/` that was selected (if on the path) or a sanitized version of the input type (e.g., "config" → "config_1").
    - If the destination folder already exists in `inputs/`, the wizard will skip copying and use the existing folder, but show a warning in the "Status" column.
  - Validation status is shown in the "Status" column (e.g., "Valid", "Missing XML", "File not found").
    - green if valid, yellow if warning (e.g., destination folder already exists), red if invalid.
- Only after all required inputs are valid can the user click "Import" to perform the copying and finalize the import process.
- After import, shows the code snippet to access the imported folders via `InputFolders` and a button to copy it to clipboard.

---

## Feature: Parameter Variation

**One-line description:** Specify multi-dimensional parameter sweeps over PhysiCell XML config values.

**User story:** As a researcher, I want to run structured parameter variations so that I can understand how input parameters affect model outputs such as cell counts, time series, and spatial metrics.

**Behavioral specification:**
- `DiscreteVariation(xml_path, values)` — explicit list of values for one parameter.
- `GridVariation()` — a method singleton, passed as the *leading* argument to `createTrial`/`run` to take the full Cartesian product of the variations that follow. It is the default, so it is usually omitted.
- `LHSVariation`, `SobolVariation`, `RBDVariation` — space-filling designs over continuous ranges.
- `DistributedVariation` — sample from a probability distribution.
- `LatentVariation` — parameterize one or more XML paths through one or more latent parameters (each a value vector or a distribution) via user-supplied maps.
- `CoVariation` — link multiple parameters so they vary together.
- Variation objects accept an optional `name` field for user-defined display names in parameter DataFrames and sensitivity scheme outputs.
- If `name` is omitted, defaults follow `shortVariationName` conventions based on location + target XML path.
- Variations are passed to `run()` to generate a `Monad`/`Sampling`/`Trial` hierarchy.

**Acceptance criteria:**
- A `GridVariation` over N×M discrete values produces exactly N×M distinct `Monad`s.
- `xml_path` helpers (`configPath`, `behaviorPath`, etc.) produce valid XPath-like strings accepted by variation constructors.
- Sensitivity scheme CSV/DataFrame headers use variation names (user-specified when present; convention-based defaults otherwise).

**Edge cases:**
- Duplicate parameter paths in a single variation → error.
- LHS/Sobol/RBD with n_samples=0 → error.

---

## Feature: Simulation Execution

**One-line description:** Compile and run PhysiCell simulations, locally or on an HPC cluster.

**Behavioral specification:**
- `run(inputs; n_replicates=1)` runs a single parameter point with replication.
- `run(inputs, variation; n_replicates=N)` sweeps over all variation points.
- Local execution: spawns PhysiCell subprocesses, up to `setNumberOfParallelSims` (or `PCMM_NUM_PARALLEL_SIMS`) at a time.
- HPC execution: PCMM supplies the simulation command via `simulationCommand`; ModelManager submits it (`sbatch --wrap`, no script file is written) and detects completion with a filesystem sentinel. PBS/`qsub` support is deferred — see the `-march` to-do in CLAUDE.md.
- PCMM implements ModelManager's `simulationThreads` from the simulation's `parallel/omp_num_threads` (read through the variation record, so a varied thread count is honoured), because PhysiCell starts that many threads regardless of what SLURM allocated; ModelManager's default `cpus-per-task` job option requests it per submission. A config whose element cannot be read falls back to 1 with one warning; a user's own `cpus-per-task` replaces the default.
- A submission `sbatch` refuses is ModelManager's to handle (retried when transient, otherwise the run stops with the scheduler's message); it is never recorded as a failed PhysiCell simulation.
- Returns an `MMOutput` (alias `PCMMOutput`) wrapping the trial object, with the counts of simulations scheduled and completed.

**Acceptance criteria:**
- Completed simulations write PhysiCell output to the folder `pathToOutputFolder` returns — `data/outputs/simulations/<simulation_id>/output/` — with `output.log`/`output.err` beside it in the simulation folder. Use the accessor rather than the literal path; the layout is ModelManager's.
- Database records each simulation with status (queued / running / completed / failed).
- Rerunning an already-completed simulation with identical inputs is a no-op.
- The compiled executable is named for the PhysiCell version it was built against (`pcmm_build/project_<physicell-version>` inside the custom code folder), and its presence is the only record that a build for that version succeeded. Recompilation happens when that file is absent, when the required macros differ from those recorded by the last successful compilation, or when the PhysiCell version cannot be pinned down (a dirty or downloaded PhysiCell).
- The PhysiCell version is re-resolved from disk before every compilation, not only at initialization. A PhysiCell that is pulled, checked out, or edited mid-session is compiled for — and recorded as — what it is at that moment, with no restart required.

**Edge cases:**
- PhysiCell binary not compiled → error with instructions.
- Simulation process exits non-zero → mark as failed in database, do not crash caller.
- IC cell or IC ECM setup fails → the simulation is marked failed without ever launching, and the cause is written to its `output.err`, which is the file the run's closing summary tells the user to check. A `@warn` names the simulation, the cause and that file as well.
- `n_replicates` < 0 → `AssertionError`. Zero is legal: it registers the monad without launching simulations, which is what the calibration reference-monad idiom relies on.
- Compilation fails → the run fails, and nothing is left that a later run could read as a finished build: any executable for this PhysiCell version is deleted, including one that predated this compilation, and the macros file is left as the last successful compilation wrote it. The next run recompiles instead of reusing a stale executable. `compilation.log` / `compilation.err` are left in place for inspection.
- Compilation reports success but produces no executable → treated as a failure.
- A `data/` folder is moved to a machine with a different OS, architecture, or compiler → **not** detected; the executable name carries no ISA component. See [Known limitations](docs/src/man/known_limitations.md).
- PhysiCell changes mid-session → detected at the next compilation. The check runs once per sampling, so a `Trial` spanning several samplings can straddle two PhysiCell versions; each sampling records the version it was actually built against.

---

## Feature: Simulation Output Loading

**One-line description:** Load PhysiCell simulation output (cells, substrates, mesh, attachment/spring/neighbor graphs) into Julia objects, addressable by simulation ID.

**Behavioral specification:**
- Path-based loading is provided by the external **PhysiCellOutput.jl** package (re-exported): `PhysiCellSnapshot`, `PhysiCellSequence`, `AbstractPhysiCellSequence`, `cellDataSequence`, `cellLabels`, `cellTypeToNameDict`, `substrateNames`, `loadCells!`, `loadSubstrates!`, `loadMesh!`, `loadGraph!`, `pathToOutputFileBase`, `pathToOutputXML`, `AgentID`, `AgentDict`.
- PCMM adds database-identity entry points on top of these: the same functions accept a `simulation_id::Integer` or a `Simulation`, converting to an output folder via `pathToOutputFolder` before delegating to PhysiCellOutput. Examples: `PhysiCellSnapshot(sim_id, index; include_cells=true)`, `PhysiCellSequence(simulation)`, `cellDataSequence(sim_id, ["position", "total_volume"])`.
- `include_*` keyword arguments (`include_cells`, `include_substrates`, `include_mesh`, `include_attachments`, `include_spring_attachments`, `include_neighbors`) control eager loading; omitted data can be loaded later with the `load*!` mutators.

**Acceptance criteria:**
- The id-/`Simulation`-based API returns the same objects PhysiCellOutput's path-based API returns for the corresponding output folder.
- Loaded values match the raw PhysiCell `.mat`/`.xml` output.

**Edge cases:**
- Missing output file (e.g. a pruned simulation) → returns `missing` with a printed message rather than throwing.
- A project must be initialized before id-based loading; PCMM's entry points call `assertInitialized()` first so the error is clear.
- Zero-cell snapshots load correctly (relies on `MAT ≥ 0.12.1`).

---

## Feature: Analysis — Population Dynamics

**One-line description:** Compute cell population counts and time series from completed simulations.

**Behavioral specification:**
- `finalPopulationCount(sim_id)` → `Dict{String,Int}` of cell type → count at final time point.
- `finalPopulationCount(monad)` → `Dict{String,Float64}` averaged across replicates.
- `populationTimeSeries(sim_id)` → time-indexed counts per cell type.
- `meanPopulationTimeSeries(monad_id)` → mean time series across replicates.
- `populationCount(sim_id, t)` → counts at a specific time point.
- All functions accept `include_dead=true` to include dead cells.
- Replicates whose output is no longer on disk (deleted or pruned) are **excluded** from monad-level aggregates, and their exclusion is reported once per call site with `@info ... maxlog=1`. Pruning is a deliberate user action, so this is informational, not a warning.
- A plot's cell-type roster is read from the first simulation in the trial whose initial-snapshot XML is still on disk — not from the trial's first simulation unconditionally — so pruning any one replicate does not change which panels are drawn.
- Plot recipes are provided for `Simulation`, `Monad`, `Sampling`, `Trial`, `run` results, and `plotbycelltype`. The manual shows rendered figures for three of these — the per-monad, per-cell-type and single-simulation plots — and for ModelManager's sensitivity-analysis (MOAT, Sobol', RBD) and calibration (corner, ridgeline, convergence, transition) recipes, all generated by `docs/generate_figures.jl` on the test project; the rest are described in prose.

**Acceptance criteria:**
- Results match values read directly from PhysiCell SVG/output files.
- Empty monad (no simulations) → error, not silent zero.
- A monad with some replicates' output removed still returns a value, computed over the survivors, and says so once.
- The user manual displays at least one rendered figure per plot recipe.

**Edge cases:**
- Simulation has no output files → error with simulation ID.
- Requested cell type not present in output → return 0 / empty entry.
- `include_dead=false` is default; dead cells excluded from all counts unless specified.
- Replicates of a monad are **assumed** to declare the same cell-type roster (they share a config, and the roster is read from the output XML). PCMM does not verify this: a ragged roster requires hand-editing files under `data/`, which `best_practices.md` forbids.
- A monad-level plot with some replicates' output removed averages over the survivors only; the removed replicates are not counted in the denominator.
- Every simulation in a trial pruned or deleted → `plotbycelltype` throws an `ArgumentError` naming the trial, rather than drawing an empty figure.
- Pruning degrades the analysis functions asymmetrically, by design: `meanPopulationTimeSeries` reads a `summary/population_time_series.csv` cache that survives any prune; `finalPopulationCount` reads `final.xml`/`final.mat`, has no cache, and does **not** fall back to the time series' last row (that row is the last full-save interval, not the simulation's true end, so the substitution would be undetectable).

---

## Feature: Sensitivity Analysis

**One-line description:** Global sensitivity analysis (MOAT, Sobol', RBD) of PhysiCell outputs with respect to varied parameters.

**Behavioral specification:**
- The designs, the indices, and `calculateGSA!` live in ModelManager. PCMM adds its `QoI` builders and the PhysiCell measurement functions a user writes, and nothing else.
- `run(method, inputs_or_reference, variations; n_replicates, functions=[...])`, with `method` one of `MOAT(n)`, `Sobolʼ(n)` (alias `SobolMM`) or `RBD(n)`, runs the design and computes one sensitivity analysis per measurement. `inputs_or_reference` is an `InputFolders` or a reference `Monad`.
- A measurement is a function of one `Simulation` whose per-replicate values reduce to a `Real`, or a `QoI` whose `reduce` returns a `Real` or a `Dict`/`NamedTuple` of `Real`s. A keyed result is spread into one analysis per key, labelled `"<qoi name>.<key>"`; `ModelManager.gsaLabels(sampling)` lists the labels and `sampling.results[label]` holds each analysis.
- `endpointPopulationCountQoI` and `endpointPopulationFractionQoI` are valid measurements: one analysis per cell type, keyed by the model's cell-type roster from the snapshot metadata, so a type driven extinct by some parameter set still reports zero rather than dropping its key.

**Acceptance criteria:**
- Sensitivity indices sum to approximately 1 for well-behaved models.
- Results are reproducible given the same seed.
- A keyed measurement yields exactly one label per key.

**Edge cases:**
- Output quantity is constant across all runs → indices are all zero, no error.
- A `Vector`-valued measurement, or a keyed measurement with a non-`Real` component (`meanPopulationTimeSeriesQoI`) → `ArgumentError` naming the QoI; reduce to a scalar first.
- Key sets that differ across the design → refused, not filled in.

---

## Feature: Calibration Summary Statistics

**One-line description:** PhysiCell-specific summary statistics for use with ModelManager's `CalibrationProblem`.

**Behavioral specification:**
- All calibration infrastructure (ABC-SMC algorithm, `CalibrationProblem`, `runABC`, `resumeABC`, kernels, posterior visualization) lives in ModelManager. PCMM contributes the PhysiCell-specific measurements passed as `summary_statistic` in a `CalibrationProblem`.
- **A summary statistic measures one simulation.** Every measurement function — `summary_statistic`, sensitivity analysis's `functions=`, a `post_processor`, a `QoI`'s `compute` — receives a `Simulation`, and ModelManager reduces a parameter set's replicates. The three monad-level functions below take a monad ID, do their own averaging, and are for direct analysis of a finished monad; they are **not** valid `summary_statistic` arguments, and the `QoI` builders fill that role.
- `endpointPopulationCounts(monad_id; cell_types, include_dead)` → `Dict{String,Float64}` mapping cell type → mean final count across replicates. Returns `missing` if no simulation output is available.
- `endpointPopulationFractions(monad_id; cell_types, include_dead)` → `Dict{String,Float64}` mapping cell type → mean fraction of total live cells. Returns `missing` if no output available.
- `meanPopulationTimeSeries(monad_id; cell_types, include_dead)` → `Dict{String,Vector{Float64}}` mapping cell type → mean count over time across replicates.
- Each statistic also has a builder returning a single `QoI` — `endpointPopulationCountQoI`, `endpointPopulationFractionQoI`, `meanPopulationTimeSeriesQoI` — whose value is a `Dict` keyed by cell type, the same shape as the monad-level statistic, so `observed_data` does not change. Calibration hands `distance` a `SummaryValues` in which a bare cell-type key resolves while only one QoI reports it, so `observed_data` stays keyed by cell type for `mseDistance`. Each builder's keyword arguments travel in the QoI's `data` slot and its `compute`/`reduce` are named top-level functions, so a `problem.jld2` written from a builder is complete and `resumeABC(Calibration(id))` needs no `problem=`.
- `cell_types` is optional: omitted, the builder measures every cell type in the output, exactly as the monad-level function does.
- **Which builder reaches which consumer.** Every builder — `endpointPopulationCountQoI`, `endpointPopulationFractionQoI`, `populationCountQoI` — serves all three consumers: calibration, the post-processing sink (one `<qoi name>.<cell_type>` column per key) and sensitivity analysis (one analysis per key, labelled `<qoi name>.<key>` and retrieved from `results` by that label; `gsaLabels` lists them). The exception is `meanPopulationTimeSeriesQoI`, which serves calibration alone: its `compute` returns a `SimulationPopulationTimeSeries`, which is not a scalar, `NamedTuple` or `AbstractDict` and so cannot be stored by the sink, and each component of its `reduce` is a series rather than the `Real` a sensitivity index is computed from.
- `populationCountQoI` defines no `reduce`, so wherever it is reduced across replicates ModelManager's default per-key mean applies, and that default refuses a monad whose replicates report different cell types where the endpoint builders zero-fill.
- Sensitivity analysis requires every parameter set in a design to reduce to the *same* keys. PCMM's builders satisfy this by construction: the key set is the model's own cell-type roster from the snapshot metadata, not the set of types with living cells, so a type driven extinct by some parameter set still reports zero rather than dropping its key.
- **`cell_types` is applied by `compute`, not only by `reduce`.** The sink calls `compute` and never `reduce`, so a builder filtering in its reducer alone would write a column per cell type and silently ignore the argument. For fractions the denominator is still every live cell: the total is summed before the restriction, matching `endpointPopulationFractions`.
- Future PhysiCell-specific statistics (spatial metrics, intracellular state distributions, etc.) would be added here.

**Acceptance criteria:**
- `endpointPopulationCounts(monad_id)` returns a `Dict{String,Float64}` for a monad with completed simulations.
- `endpointPopulationCounts` returns `missing` gracefully when simulation output files are absent.
- Fractions sum to 1.0 (within floating-point tolerance) when `include_dead=false`.
- `cell_types` filter restricts output to only the requested types.

**Edge cases:**
- All replicates in a monad have missing output → return `missing`, not an error.
- `cell_types` filter names a type not present in the simulation → entry is omitted from result.
- Some replicates missing output → averaged over the survivors, reported once via `@info ... maxlog=1`. `maxlog` is required: calibration evaluates these once per monad across thousands of particles.
- A builder returns **exactly** what its monad-level counterpart returns (`==`, not `isapprox`); each builder carries its own reducer because the three statistics disagree about whether an absent cell type is zero-filled and about summation order, and a shared reducer would silently change results. The one deliberate difference: where every replicate is missing, `meanPopulationTimeSeriesQoI` returns `missing` while `meanPopulationTimeSeries` raises a `KeyError`.

---

## Feature: Database Management

**One-line description:** Maintain an SQLite database recording all simulations, variations, and their relationships.

**Behavioral specification:**
- Schema is created on `createProject` and migrated forward on `initializeModelManager` via `src/up.jl`.
- Every simulation, monad, sampling, and trial is assigned a stable integer ID.
- `databaseDiagnostics()` validates referential integrity.

**Acceptance criteria:**
- No orphaned records after normal use.
- `up.jl` migrations are idempotent.
- Migrations are exercised end-to-end in CI: a project created by an older released version can be opened by a newer version with `auto_upgrade=true` without data loss (see *Upgrade-path CI* below).

**Edge cases:**
- Schema version mismatch → migrate up, never silently corrupt.
- Database file locked by another process → error with message, not silent hang.

### Sub-feature: Upgrade-path CI

**One-line description:** A dedicated GitHub Actions workflow that replays real version history — generate a project with an older *released* package version, then upgrade it with a newer version — to guard `src/up.jl` against regressions.

**Why a separate workflow:** the test needs two different package versions present (one to write legacy data, one to upgrade it), which cannot coexist inside a single `Pkg.test()` environment. It runs on the same triggers as `CI.yml`.

**Behavioral specification:**
- A *generation* step installs a pinned older release in an isolated environment and produces a real `data/` project (DB + simulation outputs) stamped at that older version.
- An *upgrade + verify* step opens that same project with the **dev checkout** (`auto_upgrade=true`), which runs every `src/up.jl` milestone between the source version and dev `HEAD`, then asserts data integrity directly against the SQLite database.
- The source version is a single parameter (a CI matrix entry) so the upgrade history can be "walked back" incrementally. The primary target is `0.1.7` → `HEAD` (the oldest version a real user is currently on; crosses the `0.2.0` par_key rewrite and `0.3.0`), with `0.2.2` → `HEAD` kept to isolate the `0.3.0` hop. Eventual target: back to the oldest installable release `pcvct@0.0.3`.

**Acceptance criteria:**
- After upgrade, `simulations` / `monads` / `samplings` row counts equal the pre-upgrade snapshot (no data loss).
- The version table is stamped with the dev `HEAD` version.
- Output folders referenced by surviving simulations still exist on disk.
- The upgrade completes without error crossing each milestone in range.

**Edge cases / notes:**
- Versions `< 0.1.0` were published under the package name `pcvct` (UUID `3c374bc7…`); `≥ 0.1.0` under `PhysiCellModelManager` (UUID `7582d1aa…`). The harness derives the package name from the source version. `0.0.1`/`0.0.2` were never released, so `pcvct@0.0.3` is the floor.
- Some milestone effects are also produced by normal `initializeDatabase` (e.g. `upgradeToV0_3_0`'s `calibrations` table), so the primary guarantee of the early hops is data preservation, not migration-specific schema deltas; the latter become testable as the source version moves back through data-transforming milestones (`upgradeToV0_2_0`, the `vct.db`→`pcmm.db` rename, etc.).

---

## Feature: Export & Pruning

**One-line description:** Export simulation outputs to portable formats and prune redundant data.

**Behavioral specification:**
- `exportSimulation(sim, dest)` copies output files to a named destination folder.
- `run(...; prune_options=PruneOptions(...))` deletes the named file types (`prune_svg`, `prune_mat`, `prune_txt`, `prune_xml`) from each simulation's output as it finishes, after the `post_processor` has run; `initial*` and `final*` files survive unless `prune_initial`/`prune_final` are set. Documented on the manual's post-processing page, as the last of the steps that follow a simulation.

**Acceptance criteria:**
- Exported folder is self-contained (no references back to PCMM database).
- Pruning does not delete the final time-point output unless `prune_final=true`.

**Edge cases:**
- Destination folder already exists → error or overwrite depending on flag.
- Pruning a not-yet-completed simulation → error.

---

## Feature: Movie Generation

**One-line description:** Render a simulation's SVG snapshots into a movie via the PhysiCell Makefile's `jpeg`/`movie` targets.

**Behavioral specification:**
- `makeMovie(simulation_id)` invokes `make jpeg` then `make movie` in `physicellDir()`, deletes the intermediate JPEGs, and leaves `out.mp4` in the simulation's output folder.
- `makeMovie(T::AbstractTrial)` / `makeMovie(out::PCMMOutput)` batch this over every simulation in the trial/output.
- `makeMovie(simulation_ids::AbstractVector{<:Integer})` (e.g. `makeMovie(4:7)`) and `makeMovie(Ts::AbstractVector{<:AbstractTrial})` (e.g. `makeMovie(Simulation.(4:7))`) batch over an explicit collection; the trial-vector form flattens to IDs via `simulationIDs`.
- Keyword arguments `framerate`, `magick_density`, `magick_resize_x`, `magick_resize_y` forward directly to the Makefile's `FRAMERATE`, `MAGICK_DENSITY`, `MAGICK_RESIZE_X`, `MAGICK_RESIZE_Y` variables (`movie`/`jpeg` targets respectively). Each defaults to `missing`, in which case the Makefile's own default for that variable is used unchanged.
- `magick_path`/`ffmpeg_path` locate the ImageMagick/FFmpeg executables; `verbose` prints the underlying `make` command output.

**Acceptance criteria:**
- Omitting the framerate/density/resize keywords leaves the Makefile's own default for each variable in place.
- Passing any of the four keywords changes the corresponding `make` invocation's variable assignment and is reflected in the produced movie.
- Re-running `makeMovie` when `out.mp4` already exists is a no-op (`false` return), regardless of these keywords.

**Edge cases:**
- No `s*.svg` files in the output folder → warn and skip (`false` return), independent of these keywords.
- ImageMagick or FFmpeg not discoverable on `PATH` → throws `ErrorException`.

---

## Feature: Post-Processing Hook & Quantities of Interest

**One-line description:** Let users compute per-simulation quantities of interest (QoIs) from intact output via a `post_processor` callback, and guarantee that PCMM's destructive pruning runs only after that callback.

**Background:** ModelManager runs three per-simulation post steps in order:
`postSimulationProcessing` (non-destructive) → user `post_processor` (successful sims only) → `postSimulationCleanup` (destructive). PCMM implements the destructive step (err-file handling + `pruneSimulationOutput`) as `postSimulationCleanup` so a `post_processor` always reads an un-pruned output folder. `postSimulationProcessing` is left as ModelManager's no-op default.

**Behavioral specification:**
- `run(T; post_processor = f)` calls the callback once per successful simulation, after the simulation finishes and before pruning.
- The callback receives a `Simulation` — the same argument a `QoI`'s `compute` gets, since every measurement function shares one contract. Most loader and analysis functions take it directly; `simulationID(sim)` and `pathToOutputFolder(sim)` give the ID and the folder.
- Return patterns: `missing` (side effects only — must be explicit; `nothing`, the value a block returns by accident, is refused), a bare scalar (`Real`/`Bool`/`String`, stored under the QoI's own name), or a `NamedTuple`/`Dict` of `name => scalar`. Non-scalar returns throw `ArgumentError` (ModelManager-side).
- A spread return writes one column per key named `<qoi name>.<key>`, so a callback that stores anything must carry a stable name — an anonymous `sim -> …` is refused, since its derived name varies between sessions. Wrap it in a `QoI` or pass a named function; a callback returning `missing` is unaffected.
- Stored QoIs land in `data/outputs/postprocessing.db`; read back with `postProcessingTable(T)` or `simulationsTable(T; post_processing=true)`.
- **QoI builder:** `populationCountQoI(; index=:final, cell_types=nothing, include_dead=false)` returns a ready-made `post_processor` recording one `population_count.<cell_type>` column per cell type, read from the snapshot at `index` (`:final`, `:initial`, or an integer snapshot index). The key is the bare cell type: ModelManager supplies the `<qoi name>.` namespace, so a `count_` prefix would only produce `population_count.count_<cell_type>`.

**Acceptance criteria:**
- A `post_processor` reading `pathToOutputFolder(sim)` sees output files present; those files are pruned only after it returns.
- A run without a `post_processor` still prunes, in the same step and with the same result.
- `postSimulationCleanup` runs for every completed simulation, including failures.
- `populationCountQoI()` matches `finalPopulationCount` at the default `:final` index and `populationCount` at any integer index; an optional `cell_types` filter restricts which cell types are recorded. Its sink columns are `population_count.<cell_type>`.

**Edge cases:**
- Callback on a failed simulation → not called (successful sims only); cleanup still runs.
- Callback returns a non-scalar → `ArgumentError`.
- Anonymous callback returns something storable → `ArgumentError`, because every column is named after its QoI and a derived name is not stable across sessions. Returning `missing` is unaffected.
- Callback returns `nothing` → `ArgumentError` asking for `missing`.
- `populationCountQoI`'s requested snapshot doesn't exist (e.g. pruned) → returns `missing` for that simulation instead of throwing; nothing is recorded for it.

---

## Feature: PhysiCell Studio Integration

**One-line description:** Launch PhysiCell Studio against a completed simulation's output for interactive inspection.

**Behavioral specification:**
- `runStudio(simulation_id | Simulation | PCMMOutput{Simulation})` writes temporary config and rules files into the simulation's output folder, launches Studio, and removes the temporary files afterwards.
- The Python interpreter and Studio directory come from `PCMM_PYTHON_PATH` / `PCMM_STUDIO_PATH`, or from the `python_path` / `studio_path` keywords, which are then remembered for the session.
- The intent is visualization of results, not modification of the simulation.

**Acceptance criteria:**
- Temporary files are cleaned up whether or not the launch succeeds.
- A launch failure raises a typed PCMM error carrying the command and the underlying cause.

**Edge cases:**
- `python_path` or `studio_path` unset and not supplied → `ArgumentError` naming the missing one.
- The Python executable cannot be spawned (bad path) → typed PCMM error.
- Studio runs but exits non-zero → typed PCMM error. Both failure modes must be covered; `run` raises a different exception type for each (`Base.IOError` vs `ProcessFailedException`).
- The simulation's parsed rules file is absent → Studio still launches, without rules.

---

## Feature: Error Handling — Typed Exceptions

**One-line description:** PCMM's own failure modes raise typed exceptions so that a GUI can catch them programmatically.

**Behavioral specification:**
- `PCMMException` is an abstract supertype; every PCMM-specific exception subtypes it. A caller can catch `PCMMException` for "PCMM said no" or a concrete type for a specific condition.
- Concrete types cover: no project found; PhysiCell Studio failed to launch. The set grows only when a genuinely reachable failure needs to be distinguished.
- Each carries the identifiers a caller needs to act rather than only a message string, to the extent its condition has any: `PCMMStudioLaunchError` carries the `Cmd` and the underlying `cause`, while `PCMMMissingProject` carries only a message, because "no project here" has no further identifier to report.

**Acceptance criteria:**
- Every PCMM-specific exception is catchable both as its concrete type and as `PCMMException`.
- Adding the supertype does not break existing code catching a concrete type.
- Failures originating in a dependency's own contract (e.g. a PhysiCellXMLRules assertion) are either prevented by PCMM checking first, or wrapped in a typed PCMM error — they do not escape raw.

**Edge cases:**
- A dependency assertion that fires because PCMM called it with input it should have rejected is a PCMM bug, not a candidate for wrapping; the call is prevented instead.

---

## Non-Functional Requirements

### Reliability
- **Failure isolation:** A single failed simulation must not halt remaining queued simulations in a campaign. Failed runs are marked in the database; the run loop continues.
- **Idempotency:** Import, compilation, and database migrations must be safe to re-run against already-processed inputs without side effects.
- **Atomic status tracking:** Partial simulation output must never be treated as a completed run. Database status is the authoritative source of truth.

### Platform Compatibility
| Platform | Support Level |
|---|---|
| macOS | Fully supported |
| Linux | Fully supported (primary CI target) |
| Windows | Fully supported |
| Slurm HPC (`sbatch`) | Fully supported |
| PBS HPC (`qsub`) | Deferred |

---

## Deferred work

- Import wizard (see Feature: Model Import Wizard).
- PBS/`qsub` and a generalised scheduler; SLURM and local execution are the supported paths.
- PhysiPKPD as an input location (dosing schedules: representation, placement under `inputs/`, participation in variation).
- Generalisation beyond PhysiCell, including splitting ModelManager's exports into a developer API and a re-exportable user API.
- Workflow templates: at least one reproducible end-to-end tutorial workflow usable from a clean checkout.

---

## Open Questions & Assumptions

### Open Questions
1. **Model Manager Studio scope:** The PCMM GUI companion (Model Manager Studio) is partially implemented. Which PCMM features should be accessible through it?
2. **Windows CI validation:** Windows support is targeted but not yet validated in CI. Build environment and compiler chain need to be confirmed.
3. **PhysiPKPD inputs:** PhysiPKPD is not yet representable as a PCMM input location. Needs a design covering how dosing schedules are described, where they live under `inputs/`, and how they participate in parameter variation.

### Assumptions
1. Users are responsible for providing a working `g++` compiler; PCMM does not manage compiler installation.
2. Primary deployment is on researcher workstations or HPC clusters; cloud-native execution is not targeted.

